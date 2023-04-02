####
# Associated
####


"""
    AssociatedWeighted(P)

We normalise so that `orthogonalityweight(::Associated)` is a probability measure.
"""
struct AssociatedWeight{T,OPs<:AbstractQuasiMatrix{T}} <: Weight{T}
    P::OPs
end
axes(w::AssociatedWeight) = (axes(w.P,1),)

sum(::AssociatedWeight{T}) where T = one(T)

"""
    Associated(P)

constructs the associated orthogonal polynomials for P, which have the Jacobi matrix

    jacobimatrix(P)[2:end,2:end]

and constant first term. Or alternatively

    w = orthogonalityweight(P)
    A = recurrencecoefficients(P)[1]
    Associated(P) == (w/(sum(w)*A[1]))'*((P[:,2:end]' - P[:,2:end]) ./ (x' - x))

where `x = axes(P,1)`.
"""

struct Associated{T, OPs<:AbstractQuasiMatrix{T}} <: OrthogonalPolynomial{T}
    P::OPs
end

associated(P) = Associated(P)

axes(Q::Associated) = axes(Q.P)
==(A::Associated, B::Associated) = A.P == B.P

orthogonalityweight(Q::Associated) = AssociatedWeight(Q.P)

function associated_jacobimatrix(X::Tridiagonal)
    c,a,b = subdiagonaldata(X),diagonaldata(X),supdiagonaldata(X)
    Tridiagonal(c[2:end], a[2:end], b[2:end])
end

function associated_jacobimatrix(X::SymTridiagonal)
    a,b = diagonaldata(X),supdiagonaldata(X)
    SymTridiagonal(a[2:end], b[2:end])
end
jacobimatrix(a::Associated) = associated_jacobimatrix(jacobimatrix(a.P))

associated(::ChebyshevT{T}) where T = ChebyshevU{T}()
associated(::ChebyshevU{T}) where T = ChebyshevU{T}()


const StieltjesPoint{T,W<:Number,V,D} = BroadcastQuasiMatrix{T,typeof(inv),Tuple{BroadcastQuasiMatrix{T,typeof(-),Tuple{W,QuasiAdjoint{V,Inclusion{V,D}}}}}}
const StieltjesMatrix{T,W<:AbstractVector{<:Number},V,D} = BroadcastQuasiMatrix{T,typeof(inv),Tuple{BroadcastQuasiMatrix{T,typeof(-),Tuple{W,QuasiAdjoint{V,Inclusion{V,D}}}}}}
const LogKernelPoint{T<:Real,C,W<:Number,V,D} = BroadcastQuasiMatrix{T,typeof(log),Tuple{BroadcastQuasiMatrix{T,typeof(abs),Tuple{BroadcastQuasiMatrix{C,typeof(-),Tuple{W,QuasiAdjoint{V,Inclusion{V,D}}}}}}}}
const ConvKernel{T,D1,D2} = BroadcastQuasiMatrix{T,typeof(-),Tuple{D1,QuasiAdjoint{T,D2}}}
const Hilbert{T,D1,D2} = BroadcastQuasiMatrix{T,typeof(inv),Tuple{ConvKernel{T,Inclusion{T,D1},Inclusion{T,D2}}}}
const LogKernel{T,D1,D2} = BroadcastQuasiMatrix{T,typeof(log),Tuple{BroadcastQuasiMatrix{T,typeof(abs),Tuple{ConvKernel{T,Inclusion{T,D1},Inclusion{T,D2}}}}}}


@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, w::ChebyshevTWeight)
    T = promote_type(eltype(H), eltype(w))
    zeros(T, axes(w,1))
end

@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, w::ChebyshevUWeight)
    T = promote_type(eltype(H), eltype(w))
    convert(T,π) * axes(w,1)
end

@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, w::LegendreWeight)
    T = promote_type(eltype(H), eltype(w))
    x = axes(w,1)
    log.(x .+ one(T)) .- log.(one(T) .- x)
end

@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, wT::Weighted{<:Any,<:ChebyshevT})
    T = promote_type(eltype(H), eltype(wT))
    ChebyshevU{T}() * _BandedMatrix(Fill(-convert(T,π),1,∞), ℵ₀, -1, 1)
end

@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, wU::Weighted{<:Any,<:ChebyshevU})
    T = promote_type(eltype(H), eltype(wU))
    ChebyshevT{T}() * _BandedMatrix(Fill(convert(T,π),1,∞), ℵ₀, 1, -1)
end



@simplify function *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, wP::Weighted{<:Any,<:OrthogonalPolynomial})
    P = wP.P
    w = orthogonalityweight(P)
    A = recurrencecoefficients(P)[1]
    Q = associated(P)
    (-A[1]*sum(w))*[zero(axes(P,1)) Q] + (H*w) .* P
end

@simplify *(H::Hilbert{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, P::Legendre) = H * Weighted(P)


##
# OffHilbert
##

@simplify function *(H::Hilbert{<:Any,<:Any,<:ChebyshevInterval}, W::Weighted{<:Any,<:ChebyshevU})
    tol = eps()
    x = axes(H,1)
    T̃ = chebyshevt(x)
    ψ_1 = T̃ \ inv.(x .+ sqrtx2.(x)) # same ψ_1 = x .- sqrt(x^2 - 1) but with relative accuracy as x -> ∞
    M = Clenshaw(T̃ * ψ_1, T̃)
    data = zeros(eltype(ψ_1), ∞, ∞)
    # Operator has columns π * ψ_1^k
    copyto!(view(data,:,1), convert(eltype(data),π)*ψ_1)
    for j = 2:∞
        mul!(view(data,:,j),M,view(data,:,j-1))
        norm(view(data,:,j)) ≤ tol && break
    end
    # we wrap in a Padded to avoid increasing cache size
    T̃ * PaddedArray(chop(paddeddata(data), tol), size(data)...)
end





###
# LogKernel
###

@simplify function *(L::LogKernel{<:Any,<:ChebyshevInterval,<:ChebyshevInterval}, wT::Weighted{<:Any,<:ChebyshevT})
    T = promote_type(eltype(L), eltype(wT))
    ChebyshevT{T}() * Diagonal(Vcat(-convert(T,π)*log(2*one(T)),-convert(T,π)./(1:∞)))
end

@simplify function *(H::LogKernel, wT::Weighted{<:Any,<:SubQuasiArray{<:Any,2,<:ChebyshevT,<:Tuple{AbstractAffineQuasiVector,Slice}}})
    V = promote_type(eltype(H), eltype(wT))
    kr,jr = parentindices(wT.P)
    @assert axes(H,1) == axes(H,2) == axes(wT,1)
    T = parent(wT.P)
    x = axes(T,1)
    W = Weighted(T)
    A = kr.A
    T[kr,:] * Diagonal(Vcat(-convert(V,π)*(log(2*one(V))+log(abs(A)))/A,-convert(V,π)./(A * (1:∞))))
end



####
# StieltjesPoint
####

stieltjesmoment_jacobi_normalization(n::Int,α::Real,β::Real) = 2^(α+β)*gamma(n+α+1)*gamma(n+β+1)/gamma(2n+α+β+2)

@simplify function *(S::StieltjesPoint, w::AbstractJacobiWeight)
    α,β = w.a,w.b
    z,_ = parent(S).args[1].args
    (x = 2/(1-z);stieltjesmoment_jacobi_normalization(0,α,β)*HypergeometricFunctions.mxa_₂F₁(1,α+1,α+β+2,x))
end

@simplify function *(S::StieltjesPoint, wP::Weighted)
    P = wP.P
    w = orthogonalityweight(P)
    X = jacobimatrix(P)
    z, xc = parent(S).args[1].args
    z in axes(P,1) && return transpose(view(inv.(xc' .- xc) * wP,z,:))
    transpose((X'-z*I) \ [-sum(w)*_p0(P); zeros(∞)])
end

sqrtx2(z::Number) = sqrt(z-1)*sqrt(z+1)
sqrtx2(x::Real) = sign(x)*sqrt(x^2-1)

@simplify function *(S::StieltjesPoint, wP::Weighted{<:Any,<:ChebyshevU})
    T = promote_type(eltype(S), eltype(wP))
    z, xc = parent(S).args[1].args
    z in axes(wP,1) && return  (convert(T,π)*ChebyshevT()[z,2:end])'
    ξ = inv(z + sqrtx2(z))
    transpose(convert(T,π) * ξ.^oneto(∞))
end


@simplify function *(S::StieltjesPoint, P::Legendre)
    S * Weighted(P)
end

@simplify function *(S::StieltjesMatrix, P::AbstractQuasiMatrix)
    z = S.args[1].args[1] # vector of points to eval at
    x,ns = axes(P)
    m = length(z)
    n = length(ns)
    ret = zeros(n, m) # transpose as we fill column-by-column
    for j = 1:m
        ArrayLayouts._copyto!(view(ret,:,j),  transpose(inv.(z[j] .- x') * P))
    end
    transpose(ret)
end

####
# LogKernelPoint
####

@simplify function *(L::LogKernelPoint, wP::Weighted{<:Any,<:ChebyshevU})
    T = promote_type(eltype(L), eltype(wP))
    z, xc = parent(L).args[1].args[1].args
    if z in axes(wP,1)
        Tn = Vcat(convert(T,π)*log(2*one(T)), convert(T,π)*ChebyshevT{T}()[z,2:end]./oneto(∞))
        return transpose((Tn[3:end]-Tn[1:end])/2)
    else
        # for U_k where k>=1
        ξ = inv(z + sqrtx2(z))
        ζ = (convert(T,π)*ξ.^oneto(∞))./oneto(∞)
        ζ = (ζ[3:end]- ζ[1:end])/2

        # for U_0
        ζ = Vcat(convert(T,π)*(ξ^2/4 - (log.(abs.(ξ)) + log(2*one(T)))/2), ζ)
        return transpose(ζ)
    end

end

##
# mapped
###

@simplify function *(H::Hilbert, w::SubQuasiArray{<:Any,1})
    T = promote_type(eltype(H), eltype(w))
    m = parentindices(w)[1]
    # TODO: mapping other geometries
    @assert axes(H,1) == axes(H,2) == axes(w,1)
    P = parent(w)
    x = axes(P,1)
    (inv.(x .- x') * P)[m]
end


@simplify function *(H::Hilbert, wP::SubQuasiArray{<:Any,2,<:Any,<:Tuple{<:AbstractAffineQuasiVector,<:Any}})
    T = promote_type(eltype(H), eltype(wP))
    kr,jr = parentindices(wP)
    W = parent(wP)
    x = axes(H,1)
    t = axes(H,2)
    t̃ = axes(W,1)
    if x == t
        (inv.(t̃ .- t̃') * W)[kr,jr]
    else
        M = affine(t,t̃)
        @assert x isa Inclusion
        a,b = first(x),last(x)
        x̃ = Inclusion((M.A * a .+ M.b)..(M.A * b .+ M.b)) # map interval to new interval
        Q̃,M = arguments(*, inv.(x̃ .- t̃') * W)
        parent(Q̃)[affine(x,axes(parent(Q̃),1)),:] * M
    end
end

@simplify function *(S::StieltjesPoint, wT::SubQuasiArray{<:Any,2,<:Any,<:Tuple{<:AbstractAffineQuasiVector,<:Any}})
    P = parent(wT)
    z, x = parent(S).args[1].args
    z̃ = inbounds_getindex(parentindices(wT)[1], z)
    x̃ = axes(P,1)
    (inv.(z̃ .- x̃') * P)[:,parentindices(wT)[2]]
end

@simplify function *(L::LogKernelPoint, wT::SubQuasiArray{<:Any,2,<:Any,<:Tuple{<:AbstractAffineQuasiVector,<:Any}})
    P = parent(wT)
    z, xc = parent(L).args[1].args[1].args
    kr, jr = parentindices(wT)
    z̃ = inbounds_getindex(kr, z)
    x̃ = axes(P,1)
    c = inv(kr.A)
    LP = log.(abs.(z̃ .- x̃')) * P
    Σ = sum(P; dims=1)
    transpose((c*transpose(LP) + c*log(c)*vec(Σ))[jr])
end

@simplify function *(L::LogKernel, wT::SubQuasiArray{<:Any,2,<:Any,<:Tuple{<:AbstractAffineQuasiVector,<:Slice}})
    V = promote_type(eltype(L), eltype(wT))
    wP = parent(wT)
    kr, jr = parentindices(wT)
    x = axes(wP,1)
    T = wP.P
    @assert T isa ChebyshevT
    D = T \ (log.(abs.(x .- x')) * wP)
    c = inv(2*kr.A)
    T[kr,:] * Diagonal(Vcat(2*convert(V,π)*c*log(c), 2c*D.diag.args[2]))
end

###
# Interlace
###


@simplify function *(H::Hilbert, W::PiecewiseInterlace)
    axes(H,2) == axes(W,1) || throw(DimensionMismatch())
    Hs = broadcast(function(a,b)
                x,t = axes(a,1),axes(b,1)
                H = inv.(x .- t') * b
                H
            end, [W.args...], permutedims([W.args...]))
    N = length(W.args)
    Ts = [broadcastbasis(+, broadcast(H -> H.args[1], Hs[k,:])...) for k=1:N]
    Ms = broadcast((T,H) -> unitblocks(T\H), Ts, Hs)
    PiecewiseInterlace(Ts...) * BlockBroadcastArray{promote_type(eltype(H),eltype(W))}(hvcat, N, permutedims(Ms)...)
end


@simplify function *(H::StieltjesPoint, S::PiecewiseInterlace)
    z, xc = parent(H).args[1].args
    axes(H,2) == axes(S,1) || throw(DimensionMismatch())
    @assert length(S.args) == 2
    a,b = S.args
    xa,xb = axes(a,1),axes(b,1)
    Sa = inv.(z .- xa') * a
    Sb = inv.(z .- xb') * b
    transpose(BlockBroadcastArray(vcat, unitblocks(transpose(Sa)), unitblocks(transpose(Sb))))
end

@simplify function *(L::LogKernelPoint, S::PiecewiseInterlace)
    z, xc = parent(L).args[1].args[1].args
    axes(L,2) == axes(S,1) || throw(DimensionMismatch())
    @assert length(S.args) == 2
    a,b = S.args
    xa,xb = axes(a,1),axes(b,1)
    Sa = log.(abs.(z .- xa')) * a
    Sb = log.(abs.(z .- xb')) * b
    transpose(BlockBroadcastArray(vcat, unitblocks(transpose(Sa)), unitblocks(transpose(Sb))))
end

