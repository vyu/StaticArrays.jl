require_one_based_indexing(A...) = !Base.has_offset_axes(A...) ||
    throw(ArgumentError("offset arrays are not supported but got an array with index other than 1"))

"""
    SizedArray{Tuple{dims...}}(array)

Wraps an `AbstractArray` with a static size, so to take advantage of the (faster)
methods defined by the static array package. The size is checked once upon
construction to determine if the number of elements (`length`) match, but the
array may be reshaped.

The aliases `SizedVector{N}` and `SizedMatrix{N,M}` are provided as more
convenient names for one and two dimensional `SizedArray`s. For example, to
wrap a 2x3 array `a` in a `SizedArray`, use `SizedMatrix{2,3}(a)`.
"""
struct SizedArray{S<:Tuple,T,N,M,TData<:AbstractArray{T,M}} <: StaticArray{S,T,N}
    data::TData

    function SizedArray{S,T,N,M,TData}(a::TData) where {S<:Tuple,T,N,M,TData<:AbstractArray{T,M}}
        require_one_based_indexing(a)
        if size(a) != size_to_tuple(S) && size(a) != (tuple_prod(S),)
            throw(DimensionMismatch("Dimensions $(size(a)) don't match static size $S"))
        end
        return new{S,T,N,M,TData}(a)
    end

    function SizedArray{S,T,N,1,TData}(::UndefInitializer) where {S<:Tuple,T,N,TData<:AbstractArray{T,1}}
        return new{S,T,N,1,TData}(TData(undef, tuple_prod(S)))
    end
    function SizedArray{S,T,N,N,TData}(::UndefInitializer) where {S<:Tuple,T,N,TData<:AbstractArray{T,N}}
        return new{S,T,N,N,TData}(TData(undef, size_to_tuple(S)...))
    end
end

@inline function SizedArray{S,T,N,M}(a::AbstractArray) where {S<:Tuple,T,N,M}
    if eltype(a) == T && (M == 1 || M == ndims(a))
        a′ = M == 1 ? vec(a) : a
        return SizedArray{S,T,N,M,typeof(a′)}(a′)
    end
    return convert(SizedArray{S,T,N,M}, a)
end

@inline function SizedArray{S,T,N}(a::AbstractArray) where {S<:Tuple,T,N}
    M = ndims(a) == N ? N : 1
    return SizedArray{S,T,N,M}(a)
end

@inline (::Type{SZA})(a::AbstractArray) where {SZA<:SizedArray} = construct_type(SZA, a)(a)

# disambiguation
@inline SizedArray{S,T,N,M}(a::StaticArray) where {S<:Tuple,T,N,M} = construct_type(SizedArray{S,T,N,M}, a)(a.data)
@inline SizedArray{S,T,N}(a::StaticArray) where {S<:Tuple,T,N} = construct_type(SizedArray{S,T,N}, a)(a.data)
@inline (::Type{SZA})(a::StaticArray) where {SZA<:SizedArray} = construct_type(SZA, a)(a.data)
# TODO: Should we respect `TData`?
SizedArray{S,T,N,M,TData}(a::TData) where {S<:Tuple,T,N,M,TData<:StaticArray{<:Tuple,T,M}} = SizedArray{S,T,N,M}(a.data)

function SizedArray{S,T,N,N}(::UndefInitializer) where {S<:Tuple,T,N}
    return SizedArray{S,T,N,N,Array{T,N}}(undef)
end
function SizedArray{S,T,N,1}(::UndefInitializer) where {S<:Tuple,T,N}
    return SizedArray{S,T,N,1,Vector{T}}(undef)
end
@inline function SizedArray{S,T,N}(::UndefInitializer) where {S<:Tuple,T,N}
    return SizedArray{S,T,N,N}(undef)
end
@inline function SizedArray{S,T}(::UndefInitializer) where {S<:Tuple,T}
    return SizedArray{S,T,tuple_length(S)}(undef)
end
@generated function (::Type{SizedArray{S,T,N,M,TData}})(x::NTuple{L,Any}) where {S<:Tuple,T,N,M,TData<:AbstractArray{T,M},L}
    if L != tuple_prod(S)
        error("Dimension mismatch")
    end
    exprs = [:(a[$i] = x[$i]) for i = 1:L]
    return quote
        $(Expr(:meta, :inline))
        a = SizedArray{S,T,N,M}(undef)
        @inbounds $(Expr(:block, exprs...))
        return a
    end
end
@inline function SizedArray{S,T,N,M}(x::Tuple) where {S<:Tuple,T,N,M}
    return SizedArray{S,T,N,M,Array{T,M}}(x)
end
@inline function SizedArray{S,T,N}(x::Tuple) where {S<:Tuple,T,N}
    return SizedArray{S,T,N,N,Array{T,N}}(x)
end

# Overide some problematic default behaviour
@inline convert(::Type{SA}, sa::SizedArray) where {SA<:SizedArray} = SA(sa.data)
@inline convert(::Type{SA}, sa::SA) where {SA<:SizedArray} = sa

# Back to Array (unfortunately need both convert and construct to overide other methods)
@inline function Base.Array(sa::SizedArray{S}) where {S}
    return Array(reshape(sa.data, size_to_tuple(S)))
end
@inline function Base.Array{T}(sa::SizedArray{S,T}) where {T,S}
    return Array(reshape(sa.data, size_to_tuple(S)))
end
@inline function Base.Array{T,N}(sa::SizedArray{S,T,N}) where {T,S,N}
    return Array(reshape(sa.data, size_to_tuple(S)))
end

@inline function convert(::Type{Array}, sa::SizedArray{S}) where {S}
    return Array(reshape(sa.data, size_to_tuple(S)))
end
@inline function convert(::Type{Array}, sa::SizedArray{S,T,N,M,Array{T,M}}) where {S,T,N,M}
    return sa.data
end
@inline function convert(::Type{Array{T}}, sa::SizedArray{S,T}) where {T,S}
    return Array(reshape(sa.data, size_to_tuple(S)))
end
@inline function convert(::Type{Array{T}}, sa::SizedArray{S,T,N,M,Array{T,M}}) where {S,T,N,M}
    return sa.data
end
@inline function convert(
    ::Type{Array{T,N}},
    sa::SizedArray{S,T,N},
) where {T,S,N}
    return Array(reshape(sa.data, size_to_tuple(S)))
end
@inline function convert(::Type{Array{T,N}}, sa::SizedArray{S,T,N,N,Array{T,N}}) where {S,T,N}
    return sa.data
end

@propagate_inbounds getindex(a::SizedArray, i::Int) = getindex(a.data, i)
@propagate_inbounds setindex!(a::SizedArray, v, i::Int) = (setindex!(a.data, v, i); a)

Base.parent(sa::SizedArray) = sa.data

Base.unsafe_convert(::Type{Ptr{T}}, sa::SizedArray) where {T} = Base.unsafe_convert(Ptr{T}, sa.data)
Base.elsize(::Type{SizedArray{S,T,M,N,A}}) where {S,T,M,N,A} = Base.elsize(A)

const SizedVector{S,T} = SizedArray{Tuple{S},T,1,1}

const SizedMatrix{S1,S2,T} = SizedArray{Tuple{S1,S2},T,2}

Base.dataids(sa::SizedArray) = Base.dataids(sa.data)

function promote_rule(
    ::Type{SizedArray{S,T,N,M,TDataA}},
    ::Type{SizedArray{S,U,N,M,TDataB}},
) where {S,T,U,N,M,TDataA,TDataB}
    TU = promote_type(T, U)
    return SizedArray{S, TU, N, M, promote_type(TDataA, TDataB)}
end

function promote_rule(
    ::Type{SizedArray{S,T,N,M}},
    ::Type{SizedArray{S,U,N,M}},
) where {S,T,U,N,M,}
    TU = promote_type(T, U)
    return SizedArray{S, TU, N, M}
end

function promote_rule(
    ::Type{SizedArray{S,T,N}},
    ::Type{SizedArray{S,U,N}},
) where {S,T,U,N}
    TU = promote_type(T, U)
    return SizedArray{S, TU, N}
end


### Code that makes views of statically sized arrays also statically sized (where possible)

# Note, _get_static_vector_length is used in a generated function so it's strictly internal and can't be extended
_get_static_vector_length(::Type{<:StaticVector{N}}) where {N} = N

@generated function new_out_size(::Type{Size}, inds...) where Size
    os = []
    map(Size.parameters, inds) do s, i
        if i <: Integer
            # dimension is fixed
        elseif i <: StaticVector
            push!(os, _get_static_vector_length(i))
        elseif i == Colon || i <: Base.Slice
            push!(os, s)
        elseif i <: SOneTo
            push!(os, i.parameters[1])
        else
            error("Unknown index type: $i")
        end
    end
    return Tuple{os...}
end

@generated function new_out_size(::Type{Size}, ::Colon) where Size
    prod_size = tuple_prod(Size)
    return Tuple{prod_size}
end

function Base.view(
    a::SizedArray{S},
    indices::Union{Integer, Colon, StaticVector, Base.Slice, SOneTo}...,
) where {S}
    new_size = new_out_size(S, indices...)
    return SizedArray{new_size}(view(a.data, indices...))
end

function Base.vec(a::SizedArray{S}) where {S}
    return SizedVector{tuple_prod(S)}(vec(a.data))
end
