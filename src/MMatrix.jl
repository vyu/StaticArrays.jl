immutable MMatrix{S1, S2, T, L} <: StaticMatrix{T}
    data::NTuple{L, T}

    function MMatrix(d::NTuple{L,T})
        check_MMatrix_params(Val{S1}, Val{S2}, T, Val{L})
        new(d)
    end

    function MMatrix(d::Tuple)
        check_MMatrix_params(Val{S1}, Val{S2}, T, Val{L})
        new(convert_ntuple(T, d))
    end
end

@generated function check_MMatrix_params{S1,S2,L}(::Type{Val{S1}}, ::Type{Val{S2}}, T, ::Type{Val{L}})
    if !(T <: DataType) # I think the way types are handled in generated fnctions might have changed in 0.5?
        return :(error("MMatrix: Parameter T must be a DataType. Got $T"))
    end

    if !isa(S1, Int) || !isa(S2, Int) || !isa(L, Int) || S1 < 0 || S2 < 0 || L < 0
        return :(error("MMatrix: Sizes must be positive integers. Got $S1 × $S2 ($L elements)"))
    end

    if S1*S2 == L
        return nothing
    else
        str = "Size mismatch in MMatrix. S1 = $S1, S2 = $S2, but recieved $L elements"
        return :(error(str))
    end
end

@generated function (::Type{MMatrix{S1}}){S1,L}(x::NTuple{L})
    S2 = div(L, S1)
    if S1*S2 != L
        error("Incorrect matrix sizes. $S1 does not divide $L elements")
    end
    T = promote_tuple_eltype(x)

    return quote
        $(Expr(:meta, :inline))
        MMatrix{S1, $S2, $T, L}(x)
    end
end

@generated function (::Type{MMatrix{S1,S2}}){S1,S2,L}(x::NTuple{L})
    T = promote_tuple_eltype(x)

    return quote
        $(Expr(:meta, :inline))
        MMatrix{S1, S2, $T, L}(x)
    end
end

@generated function (::Type{MMatrix{S1,S2,T}}){S1,S2,T,L}(x::NTuple{L})
    return quote
        $(Expr(:meta, :inline))
        MMatrix{S1, S2, T, L}(x)
    end
end

@inline convert{S1,S2,T}(::Type{MMatrix{S1,S2}}, a::AbstractArray{T}) = MMatrix{S1,S2,T}((a...))

#####################
## MMatrix methods ##
#####################

@pure size{S1,S2}(::Union{MMatrix{S1,S2},Type{MMatrix{S1,S2}}}) = (S1, S2)
@pure size{S1,S2,T}(::Type{MMatrix{S1,S2,T}}) = (S1, S2)
@pure size{S1,S2,T,L}(::Type{MMatrix{S1,S2,T,L}}) = (S1, S2)

function getindex(v::MMatrix, i::Integer)
    Base.@_inline_meta
    v.data[i]
end

@propagate_inbounds setindex!{S,T}(v::MMatrix{S,T}, val, i::Integer) = setindex!(v, convert(T, val), i)
@inline function setindex!{S,T}(v::MMatrix{S,T}, val::T, i::Integer)
    @boundscheck if i < 1 || i > length(v)
        throw(BoundsError())
    end

    if isbits(T)
        unsafe_store!(Base.unsafe_convert(Ptr{T}, Base.data_pointer_from_objref(v)), val, i)
    else # TODO check that this isn't crazy. Also, check it doesn't cause problems with GC...
        unsafe_store!(Base.unsafe_convert(Ptr{Ptr{Void}}, Base.data_pointer_from_objref(v.data)), Base.data_pointer_from_objref(val), i)
    end

    return val
end

@inline Tuple(v::MMatrix) = v.data

macro MMatrix(ex)
    @assert isa(ex, Expr)
    if ex.head == :hcat
        s1 = 1
        s2 = length(ex.args)
        return Expr(:call, MMatrix{s1, s2}, Expr(:tuple, ex.args...))
    elseif ex.head == :vcat
        # Validate
        s1 = length(ex.args)
        s2s = map(i -> ((isa(ex.args[i], Expr) && ex.args[i].head == :row) ? length(ex.args[i].args) : 0), 1:s1)
        s2 = minimum(s2s)
        if maximum(s2s) != s2
            error("Rows must be of matching lengths")
        end

        exprs = [ex.args[i].args[j] for i = 1:s1, j = 1:s2]
        return Expr(:call, MMatrix{s1, s2}, Expr(:tuple, exprs...))
    end
end
