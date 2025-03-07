# This file is a part of Julia. License is MIT: https://julialang.org/license

### Common definitions

import Base: sort!, findall, copy!
import LinearAlgebra: promote_to_array_type, promote_to_arrays_
using LinearAlgebra: _SpecialArrays, _DenseConcatGroup

### The SparseVector

### Types

"""
    SparseVector{Tv,Ti<:Integer} <: AbstractSparseVector{Tv,Ti}

Vector type for storing sparse vectors. Can be created by passing the length of the vector,
a *sorted* vector of non-zero indices, and a vector of non-zero values.

For instance, the vector `[5, 6, 0, 7]` can be represented as

```julia
SparseVector(4, [1, 2, 4], [5, 6, 7])
```

This indicates that the element at index 1 is 5, at index 2 is 6, at index 3 is `zero(Int)`,
and at index 4 is 7.

It may be more convenient to create sparse vectors directly from dense vectors using `sparse` as

```julia
sparse([5, 6, 0, 7])
```

yields the same sparse vector.
"""
struct SparseVector{Tv,Ti<:Integer} <: AbstractCompressedVector{Tv,Ti}
    n::Ti              # Length of the sparse vector
    nzind::Vector{Ti}   # Indices of stored values
    nzval::Vector{Tv}   # Stored values, typically nonzeros

    function SparseVector{Tv,Ti}(n::Integer, nzind::Vector{Ti}, nzval::Vector{Tv}) where {Tv,Ti<:Integer}
        n >= 0 || throw(ArgumentError("The number of elements must be non-negative."))
        length(nzind) == length(nzval) ||
            throw(ArgumentError("index and value vectors must be the same length"))
        new(convert(Ti, n), nzind, nzval)
    end
end

SparseVector(n::Integer, nzind::Vector{Ti}, nzval::Vector{Tv}) where {Tv,Ti} =
    SparseVector{Tv,Ti}(n, nzind, nzval)

SparseVector{Tv, Ti}(::UndefInitializer, n::Integer) where {Tv, Ti}  = SparseVector{Tv, Ti}(n, Ti[], Tv[])

"""
    `FixedSparseVector{Tv,Ti<:Integer} <: AbstractCompressedVector{Tv,Ti}`

Experimental AbstractCompressedVector whose non-zero index are fixed.
"""
struct FixedSparseVector{Tv,Ti<:Integer} <: AbstractCompressedVector{Tv,Ti}
    n::Ti              # Length of the sparse vector
    nzind::ReadOnly{Ti,1,Vector{Ti}}   # Indices of stored values
    nzval::Vector{Tv}   # Stored values, typically nonzeros

    function FixedSparseVector{Tv,Ti}(n::Integer, nzind::ReadOnly{Ti,1,Vector{Ti}}, nzval::Vector{Tv}) where {Tv,Ti<:Integer}
        n >= 0 || throw(ArgumentError("The number of elements must be non-negative."))
        length(nzind) == length(nzval) ||
            throw(ArgumentError("index and value vectors must be the same length"))
        new(convert(Ti, n), nzind, nzval)
    end
end
@inline _is_fixed(::FixedSparseVector) = true
FixedSparseVector(n::Integer, nzind::ReadOnly{Ti,1,Vector{Ti}}, nzval::Vector{Tv}) where {Tv,Ti<:Integer} =
    FixedSparseVector{Tv,Ti}(n, nzind, nzval)

FixedSparseVector(n::Integer, nzind::Vector{<:Integer}, nzval::Vector) =
    FixedSparseVector(n, ReadOnly(nzind), nzval)

FixedSparseVector(s::AbstractSparseVector) = FixedSparseVector(length(s), copy(nonzeroinds(s)), copy(nonzeros(s)))

"""
inverse of fixed, should not allocate
"""
_unsafe_unfix(s::AbstractSparseVector) = s
_unsafe_unfix(s::FixedSparseVector) = SparseVector(length(s), parent(nonzeroinds(s)), nonzeros(s))

# Define an alias for a view of a whole column of a SparseMatrixCSC. Many methods can be written for the
# union of such a view and a SparseVector so we define an alias for such a union as well
const SparseColumnView{Tv,Ti}  = SubArray{Tv,1,<:AbstractSparseMatrixCSC{Tv,Ti},Tuple{Base.Slice{Base.OneTo{Int}},Int},false}
const SparseVectorView{Tv,Ti}  = SubArray{Tv,1,<:AbstractSparseVector{Tv,Ti},Tuple{Base.Slice{Base.OneTo{Int}}},false}
const SparseVectorUnion{Tv,Ti} = Union{AbstractCompressedVector{Tv,Ti}, SparseColumnView{Tv,Ti}, SparseVectorView{Tv,Ti}}
const AdjOrTransSparseVectorUnion{Tv,Ti} = LinearAlgebra.AdjOrTrans{Tv, <:SparseVectorUnion{Tv,Ti}}
const SVorFSV{Tv,Ti} = Union{SparseVector{Tv,Ti},FixedSparseVector{Tv,Ti}}
### Basic properties

length(x::SVorFSV)   = getfield(x, :n)
size(x::SVorFSV)     = (getfield(x, :n),)

function Base._simple_count(f, x::AbstractCompressedVector, init::T) where T
    init + T(count(f, nonzeros(x)) + f(zero(eltype(x)))*(length(x) - nnz(x)))
end

# implement the nnz - nzrange - nonzeros - rowvals interface for sparse vectors

nnz(x::AbstractCompressedVector) = length(nonzeros(x))
function nnz(x::SparseColumnView)
    rowidx, colidx = parentindices(x)
    return length(nzrange(parent(x), colidx))
end
nnz(x::SparseVectorView) = nnz(x.parent)

"""
    nzrange(x::SparseVectorUnion, col)

Give the range of indices to the structural nonzero values of a sparse vector.
The column index `col` is ignored (assumed to be `1`).
"""
function nzrange(x::SparseVectorUnion, j::Integer)
    j == 1 ? (1:nnz(x)) : throw(BoundsError(x, (":", j)))
end

nonzeros(x::SVorFSV) = getfield(x, :nzval)
function nonzeros(x::SparseColumnView)
    rowidx, colidx = parentindices(x)
    A = parent(x)
    @inbounds y = view(nonzeros(A), nzrange(A, colidx))
    return y
end
nonzeros(x::SparseVectorView) = nonzeros(parent(x))

nonzeroinds(x::SVorFSV) = getfield(x, :nzind)
function nonzeroinds(x::SparseColumnView)
    rowidx, colidx = parentindices(x)
    A = parent(x)
    @inbounds y = view(rowvals(A), nzrange(A, colidx))
    return y
end
nonzeroinds(x::SparseVectorView) = nonzeroinds(parent(x))

rowvals(x::SparseVectorUnion) = nonzeroinds(x)

indtype(x::SparseColumnView) = indtype(parent(x))
indtype(x::SparseVectorView) = indtype(parent(x))


function Base.sizehint!(v::SparseVector, newlen::Integer)
    sizehint!(nonzeroinds(v), newlen)
    sizehint!(nonzeros(v), newlen)
    return v
end

## similar
#
# parent method for similar that preserves stored-entry structure (for when new and old dims match)
_sparsesimilar(S::SparseVector, ::Type{TvNew}, ::Type{TiNew}) where {TvNew,TiNew} =
    SparseVector(length(S), copyto!(similar(nonzeroinds(S), TiNew), nonzeroinds(S)), similar(nonzeros(S), TvNew))
# parent method for similar that preserves nothing (for when new dims are 1-d)
_sparsesimilar(S::SparseVector, ::Type{TvNew}, ::Type{TiNew}, dims::Dims{1}) where {TvNew,TiNew} =
    SparseVector(dims..., similar(nonzeroinds(S), TiNew, 0), similar(nonzeros(S), TvNew, 0))
# parent method for similar that preserves storage space (for old and new dims differ, and new is 2d)
function _sparsesimilar(S::SparseVector, ::Type{TvNew}, ::Type{TiNew}, dims::Dims{2}) where {TvNew,TiNew}
    S1 = SparseMatrixCSC(dims..., fill(one(TiNew), last(dims)+1), similar(nonzeroinds(S), TiNew, 0), similar(nonzeros(S), TvNew, 0))
    return sizehint!(S1, min(widelength(S1), length(nonzeroinds(S))))
end

_sparsesimilar(S::FixedSparseVector, x...) = move_fixed(_sparsesimilar(_unsafe_unfix(S), x...))

# The following methods hook into the AbstractArray similar hierarchy. The first method
# covers similar(A[, Tv]) calls, which preserve stored-entry structure, and the latter
# methods cover similar(A[, Tv], shape...) calls, which preserve nothing if the dims
# specify a SparseVector or a SparseMatrixCSC result.
similar(S::AbstractCompressedVector{<:Any,Ti}, ::Type{TvNew}) where {Ti,TvNew} =
    _sparsesimilar(S, TvNew, Ti)
similar(S::AbstractCompressedVector{<:Any,Ti}, ::Type{TvNew}, dims::Union{Dims{1},Dims{2}}) where {Ti,TvNew} =
    _sparsesimilar(S, TvNew, Ti, dims)
# The following methods cover similar(A, Tv, Ti[, shape...]) calls, which specify the
# result's index type in addition to its entry type, and aren't covered by the hooks above.
# The calls without shape again preserve stored-entry structure but no storage space.
similar(S::AbstractCompressedVector, ::Type{TvNew}, ::Type{TiNew}) where{TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew)
similar(S::AbstractCompressedVector, ::Type{TvNew}, ::Type{TiNew}, dims::Union{Dims{1},Dims{2}}) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, dims)
similar(S::AbstractCompressedVector, ::Type{TvNew}, ::Type{TiNew}, m::Integer) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, (m,))
similar(S::AbstractCompressedVector, ::Type{TvNew}, ::Type{TiNew}, m::Integer, n::Integer) where {TvNew,TiNew} =
    _sparsesimilar(S, TvNew, TiNew, (m, n))

## Alias detection and prevention
using Base: dataids, unaliascopy
Base.dataids(S::SparseVector) = (dataids(nonzeroinds(S))..., dataids(nonzeros(S))...)
Base.unaliascopy(S::SparseVector) = typeof(S)(length(S), unaliascopy(nonzeroinds(S)), unaliascopy(nonzeros(S)))

### Construct empty sparse vector

spzeros(len::Integer) = spzeros(Float64, len)
spzeros(dims::Tuple{<:Integer}) = spzeros(Float64, dims[1])
spzeros(::Type{T}, len::Integer) where {T} = SparseVector(len, Int[], T[])
spzeros(::Type{T}, dims::Tuple{<:Integer}) where {T} = spzeros(T, dims[1])
spzeros(::Type{Tv}, ::Type{Ti}, len::Integer) where {Tv,Ti<:Integer} = SparseVector(len, Ti[], Tv[])
spzeros(::Type{Tv}, ::Type{Ti}, dims::Tuple{<:Integer}) where {Tv,Ti<:Integer} = spzeros(Tv, Ti, dims[1])
fixed(x::AbstractSparseVector) = FixedSparseVector(x)
move_fixed(x::AbstractSparseVector) = FixedSparseVector(length(x), nonzeroinds(x), nonzeros(x))
LinearAlgebra.fillstored!(x::AbstractCompressedVector, y) = (fill!(nonzeros(x), y); x)

### Construction from lists of indices and values

function _sparsevector!(I::Vector{<:Integer}, V::Vector, len::Integer)
    # pre-condition: no duplicate indices in I
    if !isempty(I)
        p = sortperm(I)
        permute!(I, p)
        permute!(V, p)
    end
    SparseVector(len, I, V)
end

function _sparsevector!(I::Vector{<:Integer}, V::Vector, len::Integer, combine::Function)
    if !isempty(I)
        p = sortperm(I)
        permute!(I, p)
        permute!(V, p)
        m = length(I)
        r = 1
        l = 1       # length of processed part
        i = I[r]    # row-index of current element

        # main loop
        while r < m
            r += 1
            i2 = I[r]
            if i2 == i  # accumulate r-th to the l-th entry
                V[l] = combine(V[l], V[r])
            else  # advance l, and move r-th to l-th
                pv = V[l]
                l += 1
                i = i2
                if l < r
                    I[l] = i; V[l] = V[r]
                end
            end
        end
        if l < m
            resize!(I, l)
            resize!(V, l)
        end
    end
    SparseVector(len, I, V)
end

"""
    sparsevec(I, V, [m, combine])

Create a sparse vector `S` of length `m` such that `S[I[k]] = V[k]`.
Duplicates are combined using the `combine` function, which defaults to
`+` if no `combine` argument is provided, unless the elements of `V` are Booleans
in which case `combine` defaults to `|`.

# Examples
```jldoctest
julia> II = [1, 3, 3, 5]; V = [0.1, 0.2, 0.3, 0.2];

julia> sparsevec(II, V)
5-element SparseVector{Float64, Int64} with 3 stored entries:
  [1]  =  0.1
  [3]  =  0.5
  [5]  =  0.2

julia> sparsevec(II, V, 8, -)
8-element SparseVector{Float64, Int64} with 3 stored entries:
  [1]  =  0.1
  [3]  =  -0.1
  [5]  =  0.2

julia> sparsevec([1, 3, 1, 2, 2], [true, true, false, false, false])
3-element SparseVector{Bool, Int64} with 3 stored entries:
  [1]  =  1
  [2]  =  0
  [3]  =  1
```
"""
function sparsevec(I::AbstractVector{<:Integer}, V::AbstractVector, combine::Function)
    require_one_based_indexing(I, V)
    length(I) == length(V) ||
        throw(ArgumentError("index and value vectors must be the same length"))
    len = 0
    for i in I
        i >= 1 || error("Index must be positive.")
        if i > len
            len = i
        end
    end
    _sparsevector!(Vector(I), Vector(V), len, combine)
end

function sparsevec(I::AbstractVector{<:Integer}, V::AbstractVector, len::Integer, combine::Function)
    require_one_based_indexing(I, V)
    length(I) == length(V) ||
        throw(ArgumentError("index and value vectors must be the same length"))
    for i in I
        1 <= i <= len || throw(ArgumentError("An index is out of bound."))
    end
    _sparsevector!(Vector(I), Vector(V), len, combine)
end

sparsevec(I::AbstractVector, V::Union{Number, AbstractVector}, args...) =
    sparsevec(Vector{Int}(I), V, args...)

sparsevec(I::AbstractVector, V::Union{Number, AbstractVector}) =
    sparsevec(I, V, +)

sparsevec(I::AbstractVector, V::Union{Number, AbstractVector}, len::Integer) =
    sparsevec(I, V, len, +)

sparsevec(I::AbstractVector, V::Union{Bool, AbstractVector{Bool}}) =
    sparsevec(I, V, |)

sparsevec(I::AbstractVector, V::Union{Bool, AbstractVector{Bool}}, len::Integer) =
    sparsevec(I, V, len, |)

sparsevec(I::AbstractVector, v::Number, combine::Function) =
    sparsevec(I, fill(v, length(I)), combine)

sparsevec(I::AbstractVector, v::Number, len::Integer, combine::Function) =
    sparsevec(I, fill(v, length(I)), len, combine)


### Construction from dictionary
"""
    sparsevec(d::Dict, [m])

Create a sparse vector of length `m` where the nonzero indices are keys from
the dictionary, and the nonzero values are the values from the dictionary.

# Examples
```jldoctest
julia> sparsevec(Dict(1 => 3, 2 => 2))
2-element SparseVector{Int64, Int64} with 2 stored entries:
  [1]  =  3
  [2]  =  2
```
"""
function sparsevec(dict::AbstractDict{Ti,Tv}) where {Tv,Ti<:Integer}
    m = length(dict)
    nzind = Vector{Ti}(undef, m)
    nzval = Vector{Tv}(undef, m)

    cnt = 0
    len = zero(Ti)
    for (k, v) in dict
        k >= 1 || throw(ArgumentError("index must be positive."))
        if k > len
            len = k
        end
        cnt += 1
        @inbounds nzind[cnt] = k
        @inbounds nzval[cnt] = v
    end
    resize!(nzind, cnt)
    resize!(nzval, cnt)
    _sparsevector!(nzind, nzval, len)
end

function sparsevec(dict::AbstractDict{Ti,Tv}, len::Integer) where {Tv,Ti<:Integer}
    m = length(dict)
    nzind = Vector{Ti}(undef, m)
    nzval = Vector{Tv}(undef, m)

    cnt = 0
    maxk = convert(Ti, len)
    for (k, v) in dict
        1 <= k <= maxk || throw(ArgumentError("an index (key) is out of bound."))
        cnt += 1
        @inbounds nzind[cnt] = k
        @inbounds nzval[cnt] = v
    end
    resize!(nzind, cnt)
    resize!(nzval, cnt)
    _sparsevector!(nzind, nzval, len)
end


### Element access

@RCI @propagate_inbounds function setindex!(x::AbstractCompressedVector{Tv,Ti}, v::Tv, i::Ti) where {Tv,Ti<:Integer}
    @boundscheck checkbounds(x, i)
    nzind = nonzeroinds(x)
    nzval = nonzeros(x)

    m = length(nzind)
    k = searchsortedfirst(nzind, i)
    if 1 <= k <= m && nzind[k] == i  # i found
        nzval[k] = v
    else  # i not found
        if _isnotzero(v)
            insert!(nzind, k, i)
            insert!(nzval, k, v)
        end
    end
    return x
end

@RCI @propagate_inbounds setindex!(x::AbstractCompressedVector{Tv,Ti}, v, i::Integer) where {Tv,Ti<:Integer} =
    setindex!(x, convert(Tv, v), convert(Ti, i))


### dropstored!
"""
    dropstored!(x::SparseVector, i::Integer)

Drop entry `x[i]` from `x` if `x[i]` is stored and otherwise do nothing.

# Examples
```jldoctest
julia> x = sparsevec([1, 3], [1.0, 2.0])
3-element SparseVector{Float64, Int64} with 2 stored entries:
  [1]  =  1.0
  [3]  =  2.0

julia> SparseArrays.dropstored!(x, 3)
3-element SparseVector{Float64, Int64} with 1 stored entry:
  [1]  =  1.0

julia> SparseArrays.dropstored!(x, 2)
3-element SparseVector{Float64, Int64} with 1 stored entry:
  [1]  =  1.0
```
"""
function dropstored!(x::AbstractCompressedVector, i::Integer)
    if _is_fixed(x)
        x[i] = zero(eltype(x))
    else
        if !(1 <= i <= length(x::SparseVector))
            throw(BoundsError(x, i))
        end
        searchk = searchsortedfirst(nonzeroinds(x), i)
        if searchk <= length(nonzeroinds(x)) && nonzeroinds(x)[searchk] == i
            # Entry x[i] is stored. Drop and return.
            deleteat!(nonzeroinds(x), searchk)
            deleteat!(nonzeros(x), searchk)
        end
    end
    return x
end
# TODO: Implement linear collection indexing methods for dropstored! ?
# TODO: Implement logical indexing methods for dropstored! ?


### Conversion

# convert SparseMatrixCSC to SparseVector
function SparseVector{Tv,Ti}(s::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti<:Integer}
    size(s, 2) == 1 || throw(ArgumentError("The input argument must have a single-column."))
    SparseVector(size(s, 1), rowvals(s), nonzeros(s))
end

SparseVector{Tv}(s::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = SparseVector{Tv,Ti}(s)

SparseVector(s::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = SparseVector{Tv,Ti}(s)

FixedSparseVector(s::AbstractSparseMatrixCSC{Tv,Ti}) where {Tv,Ti} = move_fixed(SparseVector(s))

# convert Vector to SparseVector

"""
    sparsevec(A)

Convert a vector `A` into a sparse vector of length `m`.

# Examples
```jldoctest
julia> sparsevec([1.0, 2.0, 0.0, 0.0, 3.0, 0.0])
6-element SparseVector{Float64, Int64} with 3 stored entries:
  [1]  =  1.0
  [2]  =  2.0
  [5]  =  3.0
```
"""
sparsevec(a::AbstractVector{T}) where {T} = SparseVector{T, Int}(a)
sparsevec(a::AbstractArray) = sparsevec(vec(a))
sparsevec(a::AbstractSparseArray) = vec(a)
sparsevec(a::AbstractSparseVector) = vec(a)
sparse(a::AbstractVector) = sparsevec(a)

function _dense2indval!(nzind::Vector{Ti}, nzval::Vector{Tv}, s::AbstractArray{Tv}) where {Tv,Ti}
    require_one_based_indexing(s)
    cap = length(nzind)
    @assert cap == length(nzval)
    n = length(s)
    c = 0
    @inbounds for (i, v) in enumerate(s)
        if _isnotzero(v)
            if c >= cap
                cap = (cap == 0) ? 1 : 2*cap
                resize!(nzind, cap)
                resize!(nzval, cap)
            end
            c += 1
            nzind[c] = i
            nzval[c] = v
        end
    end
    if c < cap
        resize!(nzind, c)
        resize!(nzval, c)
    end
    return (nzind, nzval)
end

function _dense2sparsevec(s::AbstractArray{Tv}, initcap::Ti) where {Tv,Ti}
    nzind, nzval = _dense2indval!(Vector{Ti}(undef, initcap), Vector{Tv}(undef, initcap), s)
    SparseVector(length(s), nzind, nzval)
end

SparseVector{Tv,Ti}(s::AbstractVector{Tv}) where {Tv,Ti} =
    _dense2sparsevec(s, convert(Ti, max(8, div(length(s), 8))))

SparseVector{Tv}(s::AbstractVector{Tv}) where {Tv} = SparseVector{Tv,Int}(s)

SparseVector(s::AbstractVector{Tv}) where {Tv} = SparseVector{Tv,Int}(s)

# copy-constructors
SparseVector(s::AbstractCompressedVector{Tv,Ti}) where {Tv,Ti} = SparseVector{Tv,Ti}(s)
SparseVector{Tv}(s::AbstractCompressedVector{<:Any,Ti}) where {Tv,Ti} = SparseVector{Tv,Ti}(s)
function SparseVector{Tv,Ti}(s::SparseVector) where {Tv,Ti}
    copyind = Vector{Ti}(nonzeroinds(s))
    copynz = Vector{Tv}(nonzeros(s))
    SparseVector{Tv,Ti}(length(s), copyind, copynz)
end

# convert between different types of SparseVector
convert(T::Type{<:SparseVector}, m::AbstractVector) = m isa T ? m : T(m)
convert(T::Type{<:SparseVector}, m::AbstractSparseMatrixCSC) = T(m)
convert(T::Type{<:AbstractSparseMatrixCSC}, v::AbstractCompressedVector) = T(v)

### copying
function prep_sparsevec_copy_dest!(A::AbstractCompressedVector, lB, nnzB)
    lA = length(A)
    lA >= lB || throw(BoundsError())
    # If the two vectors have the same length then all the elements in A will be overwritten.
    if length(A) == lB
        resize!(nonzeros(A), nnzB)
        resize!(nonzeroinds(A), nnzB)
    else
        nnzA = nnz(A)

        lastmodindA = searchsortedlast(nonzeroinds(A), lB)
        if lastmodindA >= nnzB
            # A will have fewer non-zero elements; unmodified elements are kept at the end.
            deleteat!(nonzeroinds(A), nnzB+1:lastmodindA)
            deleteat!(nonzeros(A), nnzB+1:lastmodindA)
        else
            # A will have more non-zero elements; unmodified elements are kept at the end.
            resize!(nonzeroinds(A), nnzB + nnzA - lastmodindA)
            resize!(nonzeros(A), nnzB + nnzA - lastmodindA)
            copyto!(nonzeroinds(A), nnzB+1, nonzeroinds(A), lastmodindA+1, nnzA-lastmodindA)
            copyto!(nonzeros(A), nnzB+1, nonzeros(A), lastmodindA+1, nnzA-lastmodindA)
        end
    end
end

function copyto!(A::AbstractCompressedVector, B::AbstractCompressedVector)
    prep_sparsevec_copy_dest!(A, length(B), nnz(B))
    copyto!(nonzeroinds(A), nonzeroinds(B))
    copyto!(nonzeros(A), nonzeros(B))
    return A
end

copyto!(A::AbstractCompressedVector, B::AbstractVector) = copyto!(A, sparsevec(B))

function copyto!(A::AbstractCompressedVector, B::AbstractSparseMatrixCSC)
    prep_sparsevec_copy_dest!(A, length(B), nnz(B))

    ptr = 1
    @assert length(nonzeroinds(A)) >= length(rowvals(B))
    maximum(getcolptr(B))-1 <= length(rowvals(B)) || throw(BoundsError())
    @inbounds for col=1:length(getcolptr(B))-1
        offsetA = (col - 1) * size(B, 1)
        while ptr <= getcolptr(B)[col+1]-1
            nonzeroinds(A)[ptr] = rowvals(B)[ptr] + offsetA
            ptr += 1
        end
    end
    copyto!(nonzeros(A), nonzeros(B))
    return A
end

copyto!(A::AbstractSparseMatrixCSC, B::AbstractCompressedVector{TvB,TiB}) where {TvB,TiB} =
    copyto!(A, SparseMatrixCSC{TvB,TiB}(length(B), 1, TiB[1, length(nonzeroinds(B))+1], nonzeroinds(B), nonzeros(B)))


### Rand Construction
sprand(n::Integer, p::AbstractFloat, rfn::Function, ::Type{T}) where {T} = sprand(default_rng(), n, p, rfn, T)
function sprand(r::AbstractRNG, n::Integer, p::AbstractFloat, rfn::Function, ::Type{T}) where T
    I = randsubseq(r, 1:convert(Int, n), p)
    V = rfn(r, T, length(I))
    SparseVector(n, I, V)
end

sprand(n::Integer, p::AbstractFloat, rfn::Function) = sprand(default_rng(), n, p, rfn)
function sprand(r::AbstractRNG, n::Integer, p::AbstractFloat, rfn::Function)
    I = randsubseq(r, 1:convert(Int, n), p)
    V = rfn(r, length(I))
    SparseVector(n, I, V)
end

sprand(n::Integer, p::AbstractFloat) = sprand(default_rng(), n, p, rand)

sprand(r::AbstractRNG, n::Integer, p::AbstractFloat) = sprand(r, n, p, rand)
sprand(r::AbstractRNG, ::Type{T}, n::Integer, p::AbstractFloat) where {T} = sprand(r, n, p, (r, i) -> rand(r, T, i))
sprand(r::AbstractRNG, ::Type{Bool}, n::Integer, p::AbstractFloat) = sprand(r, n, p, truebools)
sprand(::Type{T}, n::Integer, p::AbstractFloat) where {T} = sprand(default_rng(), T, n, p)

sprandn(n::Integer, p::AbstractFloat) = sprand(default_rng(), n, p, randn)
sprandn(r::AbstractRNG, n::Integer, p::AbstractFloat) = sprand(r, n, p, randn)
sprandn(::Type{T}, n::Integer, p::AbstractFloat) where T = sprand(default_rng(), n, p, (r, i) -> randn(r, T, i))
sprandn(r::AbstractRNG, ::Type{T}, n::Integer, p::AbstractFloat) where T = sprand(r, n, p, (r, i) -> randn(r, T, i))

## Indexing into Matrices can return SparseVectors

# Column slices
function getindex(x::AbstractSparseMatrixCSC, ::Colon, j::Integer)
    checkbounds(x, :, j)
    r1 = convert(Int, getcolptr(x)[j])
    r2 = convert(Int, getcolptr(x)[j+1]) - 1
    return @if_move_fixed x SparseVector(size(x, 1), rowvals(x)[r1:r2], nonzeros(x)[r1:r2])
end

function getindex(x::AbstractSparseMatrixCSC, I::AbstractUnitRange, j::Integer)
    checkbounds(x, I, j)
    # Get the selected column
    c1 = convert(Int, getcolptr(x)[j])
    c2 = convert(Int, getcolptr(x)[j+1]) - 1
    # Restrict to the selected rows
    r1 = searchsortedfirst(rowvals(x), first(I), c1, c2, Forward)
    r2 = searchsortedlast(rowvals(x), last(I), c1, c2, Forward)
    return @if_move_fixed x SparseVector(length(I), [rowvals(x)[i] - first(I) + 1 for i = r1:r2], nonzeros(x)[r1:r2])
end

# In the general case, we piggy back upon SparseMatrixCSC's optimized solution
@inline getindex(A::AbstractSparseMatrixCSC, I::AbstractVector, J::Integer) =
    let M = A[I, [J]]
        @if_move_fixed A SparseVector(size(M, 1), rowvals(M), nonzeros(M))
    end

# Row slices
getindex(A::AbstractSparseMatrixCSC, i::Integer, ::Colon) = A[i, 1:end]
function Base.getindex(A::AbstractSparseMatrixCSC{Tv,Ti}, i::Integer, J::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, J)
    checkbounds(A, i, J)
    nJ = length(J)
    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)

    nzinds = Vector{Ti}()
    nzvals = Vector{Tv}()

    # adapted from SparseMatrixCSC's sorted_bsearch_A
    ptrI = 1
    @inbounds for j = 1:nJ
        col = J[j]
        rowI = i
        ptrA = Int(colptrA[col])
        stopA = Int(colptrA[col+1]-1)
        if ptrA <= stopA
            if rowvalA[ptrA] <= rowI
                ptrA = searchsortedfirst(rowvalA, rowI, ptrA, stopA, Base.Order.Forward)
                if ptrA <= stopA && rowvalA[ptrA] == rowI
                    push!(nzinds, j)
                    push!(nzvals, nzvalA[ptrA])
                end
            end
            ptrI += 1
        end
    end
    @if_move_fixed A SparseVector(nJ, nzinds, nzvals)
end


# Logical and linear indexing into SparseMatrices
getindex(A::AbstractSparseMatrixCSC, I::AbstractVector{Bool}) = _logical_index(A, I) # Ambiguities
getindex(A::AbstractSparseMatrixCSC, I::AbstractArray{Bool}) = _logical_index(A, I)
function _logical_index(A::AbstractSparseMatrixCSC{Tv}, I::AbstractArray{Bool}) where Tv
    require_one_based_indexing(A, I)
    checkbounds(A, I)
    n = sum(I)
    nnzB = min(n, nnz(A))

    colptrA = getcolptr(A); rowvalA = rowvals(A); nzvalA = nonzeros(A)
    rowvalB = Vector{Int}(undef, nnzB)
    nzvalB = Vector{Tv}(undef, nnzB)
    c = 1
    rowB = 1

    @inbounds for col in 1:size(A, 2)
        r1 = colptrA[col]
        r2 = colptrA[col+1]-1

        for row in 1:size(A, 1)
            if I[row, col]
                while (r1 <= r2) && (rowvalA[r1] < row)
                    r1 += 1
                end
                if (r1 <= r2) && (rowvalA[r1] == row)
                    nzvalB[c] = nzvalA[r1]
                    rowvalB[c] = rowB
                    c += 1
                end
                rowB += 1
                (rowB > n) && break
            end
        end
        (rowB > n) && break
    end
    if nnzB > (c-1)
        deleteat!(nzvalB, c:nnzB)
        deleteat!(rowvalB, c:nnzB)
    end
    return @if_move_fixed A I SparseVector(n, rowvalB, nzvalB)
end

# TODO: further optimizations are available for ::Colon and other types of AbstractRange
getindex(A::AbstractSparseMatrixCSC, ::Colon) = A[1:end]

function getindex(A::AbstractSparseMatrixCSC{Tv}, I::AbstractUnitRange) where Tv
    require_one_based_indexing(A, I)
    checkbounds(A, I)
    szA = size(A)
    nA = szA[1]*szA[2]
    colptrA = getcolptr(A)
    rowvalA = rowvals(A)
    nzvalA = nonzeros(A)

    n = length(I)
    nnzB = min(n, nnz(A))
    rowvalB = Vector{Int}(undef, nnzB)
    nzvalB = Vector{Tv}(undef, nnzB)

    if nnzB > 0
        rowstart,colstart = Base._ind2sub(szA, first(I))
        rowend,colend = Base._ind2sub(szA, last(I))

        idxB = 1
        @inbounds for col in colstart:colend
            minrow = (col == colstart ? rowstart : 1)
            maxrow = (col == colend ? rowend : szA[1])
            for r in colptrA[col]:(colptrA[col+1]-1)
                rowA = rowvalA[r]
                if minrow <= rowA <= maxrow
                    rowvalB[idxB] = Base._sub2ind(szA, rowA, col) - first(I) + 1
                    nzvalB[idxB] = nzvalA[r]
                    idxB += 1
                end
            end
        end
        if nnzB > (idxB-1)
            deleteat!(nzvalB, idxB:nnzB)
            deleteat!(rowvalB, idxB:nnzB)
        end
    end
    @if_move_fixed A SparseVector(n, rowvalB, nzvalB)
end

function getindex(A::AbstractSparseMatrixCSC{Tv,Ti}, I::AbstractVector) where {Tv,Ti}
    require_one_based_indexing(A, I)
    @boundscheck checkbounds(A, I)
    szA = size(A)
    nA = szA[1]*szA[2]
    colptrA = getcolptr(A)
    rowvalA = rowvals(A)
    nzvalA = nonzeros(A)

    n = length(I)
    nnzB = min(n, nnz(A))
    rowvalB = Vector{Ti}(undef, nnzB)
    nzvalB = Vector{Tv}(undef, nnzB)

    idxB = 1
    for i in 1:n
        row,col = Base._ind2sub(szA, I[i])
        for r in colptrA[col]:(colptrA[col+1]-1)
            @inbounds if rowvalA[r] == row
                if idxB <= nnzB
                    rowvalB[idxB] = i
                    nzvalB[idxB] = nzvalA[r]
                    idxB += 1
                else # this can happen if there are repeated indices in I
                    push!(rowvalB, i)
                    push!(nzvalB, nzvalA[r])
                end
                break
            end
        end
    end
    if nnzB > (idxB-1)
        deleteat!(nzvalB, idxB:nnzB)
        deleteat!(rowvalB, idxB:nnzB)
    end
    return @if_move_fixed A SparseVector(n, rowvalB, nzvalB)
end

Base.copy(a::SubArray{<:Any,<:Any,<:Union{SparseVector, AbstractSparseMatrixCSC}}) = a.parent[a.indices...]

function findall(x::SparseVectorUnion)
    return findall(identity, x)
end

function findall(p::F, x::SparseVectorUnion{<:Any,Ti}) where {Ti,F<:Function}
    if p(zero(eltype(x)))
        return invoke(findall, Tuple{Function, Any}, p, x)
    end
    numnz = nnz(x)
    I = Vector{Ti}(undef, numnz)

    nzind = nonzeroinds(x)
    nzval = nonzeros(x)

    count = 1
    @inbounds for i = 1 : numnz
        if p(nzval[i])
            I[count] = nzind[i]
            count += 1
        end
    end

    count -= 1
    if numnz != count
        deleteat!(I, (count+1):numnz)
    end

    return I
end
findall(p::Base.Fix2{typeof(in)}, x::SparseVectorUnion{<:Any,Ti}) where {Ti} =
    invoke(findall, Tuple{Base.Fix2{typeof(in)}, AbstractArray}, p, x)

"""
    findnz(x::SparseVector)

Return a tuple `(I, V)`  where `I` is the indices of the stored ("structurally non-zero")
values in sparse vector-like `x` and `V` is a vector of the values.

# Examples
```jldoctest
julia> x = sparsevec([1 2 0; 0 0 3; 0 4 0])
9-element SparseVector{Int64, Int64} with 4 stored entries:
  [1]  =  1
  [4]  =  2
  [6]  =  4
  [8]  =  3

julia> findnz(x)
([1, 4, 6, 8], [1, 2, 4, 3])
```
"""
function findnz(x::SparseVectorUnion{Tv,Ti}) where {Tv,Ti}
    numnz = nnz(x)

    I = Vector{Ti}(undef, numnz)
    V = Vector{Tv}(undef, numnz)

    nzind = nonzeroinds(x)
    nzval = nonzeros(x)

    @inbounds for i = 1 : numnz
        I[i] = nzind[i]
        V[i] = nzval[i]
    end

    return (I, V)
end

function _sparse_findnextnz(v::AbstractCompressedVector, i::Integer)
    n = searchsortedfirst(nonzeroinds(v), i)
    if n > length(nonzeroinds(v))
        return nothing
    else
        return nonzeroinds(v)[n]
    end
end

function _sparse_findprevnz(v::AbstractCompressedVector, i::Integer)
    n = searchsortedlast(nonzeroinds(v), i)
    if iszero(n)
        return nothing
    else
        return nonzeroinds(v)[n]
    end
end

### Generic functions operating on AbstractSparseVector

## Explicit efficient comparisons with vectors

function ==(A::AbstractCompressedVector,
            B::AbstractCompressedVector)
    # Different sizes are always different
    size(A) ≠ size(B) && return false
    # Compare nonzero elements
    i, j = 1, 1
    @inbounds while i <= nnz(A) && j <= nnz(B)
        if nonzeroinds(A)[i] == nonzeroinds(B)[j]
            nonzeros(A)[i] == nonzeros(B)[j] || return false
            i += 1
            j += 1
        elseif nonzeroinds(A)[i] <= nonzeroinds(B)[j]
            iszero(nonzeros(A)[i]) || return false
            i += 1
        else # nonzeroinds(A)[i] >= nonzeroinds(B)[j]
            iszero(nonzeros(B)[j]) || return false
            j += 1
        end
    end

    @inbounds for k in i:nnz(A)
        iszero(nonzeros(A)[k]) || return false
    end

    @inbounds for k in j:nnz(B)
        iszero(nonzeros(B)[k]) || return false
    end

    return true
end

==(A::Transpose{<:Any,<:AbstractCompressedVector},
    B::Transpose{<:Any,<:AbstractCompressedVector}) = transpose(A) == transpose(B)

==(A::Adjoint{<:Any,<:AbstractCompressedVector},
    B::Adjoint{<:Any,<:AbstractCompressedVector}) = adjoint(A) == adjoint(B)

### getindex

function _spgetindex(m::Int, nzind::AbstractVector{Ti}, nzval::AbstractVector{Tv}, i::Integer) where {Tv,Ti}
    ii = searchsortedfirst(nzind, convert(Ti, i))
    (ii <= m && nzind[ii] == i) ? nzval[ii] : zero(Tv)
end

@RCI @propagate_inbounds function getindex(x::AbstractSparseVector, i::Integer)
    @boundscheck checkbounds(x, i)
    _spgetindex(nnz(x), nonzeroinds(x), nonzeros(x), i)
end

function getindex(x::AbstractSparseVector{Tv,Ti}, I::AbstractUnitRange) where {Tv,Ti}
    checkbounds(x, I)
    xlen = length(x)
    i0 = first(I)
    i1 = last(I)

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    m = length(xnzind)

    # locate the first j0, s.t. xnzind[j0] >= i0
    j0 = searchsortedfirst(xnzind, i0)
    # locate the last j1, s.t. xnzind[j1] <= i1
    j1 = searchsortedlast(xnzind, i1, j0, m, Forward)

    # compute the number of non-zeros
    jrgn = j0:j1
    mr = length(jrgn)
    rind = Vector{Ti}(undef, mr)
    rval = Vector{Tv}(undef, mr)
    if mr > 0
        c = 0
        for j in jrgn
            c += 1
            rind[c] = convert(Ti, xnzind[j] - i0 + 1)
            rval[c] = xnzval[j]
        end
    end
    return @if_move_fixed x SparseVector(length(I), rind, rval)
end

getindex(x::AbstractSparseVector, I::AbstractVector{Bool}) = x[findall(I)]
getindex(x::AbstractSparseVector, I::AbstractArray{Bool}) = x[LinearIndices(I)[findall(I)]]
@inline function getindex(x::AbstractSparseVector{Tv,Ti}, I::AbstractVector) where {Tv,Ti}
    # SparseMatrixCSC has a nicely optimized routine for this; punt
    S = SparseMatrixCSC(length(x), 1, Ti[1,length(nonzeroinds(x))+1], nonzeroinds(x), nonzeros(x))
    return S[I, 1]
end

function getindex(x::AbstractSparseVector{Tv,Ti}, I::AbstractArray) where {Tv,Ti}
    # punt to SparseMatrixCSC
    S = SparseMatrixCSC(length(x), 1, Ti[1,length(nonzeroinds(x))+1], nonzeroinds(x), nonzeros(x))
    return S[I]
end

getindex(x::AbstractSparseVector, ::Colon) = copy(x)

function Base.isstored(x::AbstractSparseVector, i::Integer)
    @boundscheck checkbounds(x, i)
    return i in nonzeroinds(x)
end

### show and friends

function show(io::IO, ::MIME"text/plain", x::AbstractSparseVector)
    xnnz = length(nonzeros(x))
    print(io, length(x), "-element ", typeof(x), " with ", xnnz,
           " stored ", xnnz == 1 ? "entry" : "entries")
    if xnnz != 0
        println(io, ":")
        show(IOContext(io, :typeinfo => eltype(x)), x)
    end
end

show(io::IO, x::AbstractSparseVector) = show(convert(IOContext, io), x)
function show(io::IOContext, x::AbstractSparseVector)
    # TODO: make this a one-line form
    nzind = nonzeroinds(x)
    nzval = nonzeros(x)
    if isempty(nzind)
        return show(io, MIME("text/plain"), x)
    end
    limit = get(io, :limit, false)::Bool
    half_screen_rows = limit ? div(displaysize(io)[1] - 8, 2) : typemax(Int)
    pad = ndigits(nzind[end])
    if !haskey(io, :compact)
        io = IOContext(io, :compact => true)
    end
    for k = eachindex(nzind)
        if k < half_screen_rows || k > length(nzind) - half_screen_rows
            print(io, "  ", '[', rpad(nzind[k], pad), "]  =  ")
            if isassigned(nzval, Int(k))
                show(io, nzval[k])
            else
                print(io, Base.undef_ref_str)
            end
            k != length(nzind) && println(io)
        elseif k == half_screen_rows
            println(io, "   ", " "^pad, "   \u22ee")
        end
    end
end

### Conversion to matrix

function SparseMatrixCSC{Tv,Ti}(x::AbstractSparseVector) where {Tv,Ti}
    require_one_based_indexing(x)
    n = length(x)
    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    m = length(xnzind)
    colptr = Ti[1, m+1]
    # Note that this *cannot* share data like normal array conversions, since
    # modifying one would put the other in an inconsistent state
    rowval = Vector{Ti}(xnzind)
    nzval = Vector{Tv}(xnzval)
    SparseMatrixCSC(n, 1, colptr, rowval, nzval)
end

SparseMatrixCSC{Tv}(x::AbstractSparseVector{<:Any,Ti}) where {Tv,Ti} = SparseMatrixCSC{Tv,Ti}(x)
SparseMatrixCSC(x::AbstractSparseVector{Tv,Ti}) where {Tv,Ti} = SparseMatrixCSC{Tv,Ti}(x)

function Vector(x::AbstractSparseVector{Tv}) where Tv
    require_one_based_indexing(x)
    n = length(x)
    n == 0 && return Vector{Tv}()
    nzind = nonzeroinds(x)
    nzval = nonzeros(x)
    r = zeros(Tv, n)
    for k in 1:nnz(x)
        i = nzind[k]
        v = nzval[k]
        r[i] = v
    end
    return r
end
Array(x::AbstractSparseVector) = Vector(x)
    
function Base.collect(x::Union{AbstractSparseVector,AbstractSparseMatrix})
   if Base.has_offset_axes(x)
       return Base._collect_indices(axes(x), x)
   else
       return Array(x)
   end
end

Base.iszero(x::AbstractSparseVector) = iszero(nonzeros(x))

### Array manipulation

vec(x::AbstractSparseVector) = x
copy(x::AbstractSparseVector) = if _is_fixed(x)
        FixedSparseVector(length(x), nonzeroinds(x), copy(nonzeros(x)))
    else
        SparseVector(length(x), copy(nonzeroinds(x)), copy(nonzeros(x)))
    end

float(x::AbstractSparseVector{<:AbstractFloat}) = x
float(x::AbstractSparseVector) =
    SparseVector(length(x), copy(nonzeroinds(x)), float(nonzeros(x)))

complex(x::AbstractSparseVector{<:Complex}) = x
complex(x::AbstractSparseVector) =
    SparseVector(length(x), copy(nonzeroinds(x)), complex(nonzeros(x)))


### Concatenation

# Without the first of these methods, horizontal concatenations of SparseVectors fall
# back to the horizontal concatenation method that ensures that combinations of
# sparse/special/dense matrix/vector types concatenate to SparseMatrixCSCs, instead
# of _absspvec_hcat below. The <:Integer qualifications are necessary for correct dispatch.
hcat(X::SparseVector{Tv,Ti}...) where {Tv,Ti<:Integer} = _absspvec_hcat(X...)
hcat(X::FixedSparseVector{Tv,Ti}...) where {Tv,Ti<:Integer} = _absspvec_hcat(X...)
hcat(X::AbstractSparseVector{Tv,Ti}...) where {Tv,Ti<:Integer} = _absspvec_hcat(X...)
function _absspvec_hcat(X::AbstractSparseVector{Tv,Ti}...) where {Tv,Ti}
    # check sizes
    n = length(X)
    m = length(X[1])
    tnnz = nnz(X[1])
    for j = 2:n
        length(X[j]) == m ||
            throw(DimensionMismatch("Inconsistent column lengths."))
        tnnz += nnz(X[j])
    end

    # construction
    colptr = Vector{Ti}(undef, n+1)
    nzrow = Vector{Ti}(undef, tnnz)
    nzval = Vector{Tv}(undef, tnnz)
    roff = 1
    @inbounds for j = 1:n
        xj = X[j]
        xnzind = nonzeroinds(xj)
        xnzval = nonzeros(xj)
        colptr[j] = roff
        copyto!(nzrow, roff, xnzind)
        copyto!(nzval, roff, xnzval)
        roff += length(xnzind)
    end
    colptr[n+1] = roff
    r = SparseMatrixCSC{Tv,Ti}(m, n, colptr, nzrow, nzval)
    return @if_move_fixed X... r
end

# Without the first of these methods, vertical concatenations of SparseVectors fall
# back to the vertical concatenation method that ensures that combinations of
# sparse/special/dense matrix/vector types concatenate to SparseMatrixCSCs, instead
# of _absspvec_vcat below. The <:Integer qualifications are necessary for correct dispatch.
vcat(X::SparseVector{Tv,Ti}...) where {Tv,Ti<:Integer} = _absspvec_vcat(X...)
vcat(X::AbstractSparseVector{Tv,Ti}...) where {Tv,Ti<:Integer} = _absspvec_vcat(X...)
function vcat(X::SparseVector...)
    commeltype = promote_type(map(eltype, X)...)
    commindtype = promote_type(map(indtype, X)...)
    return vcat(map(x -> SparseVector{commeltype,commindtype}(x), X)...)
end
function vcat(X::SVorFSV...)
    r = vcat(map(_unsafe_unfix, X)...)
    return @if_move_fixed X r
end
function _absspvec_vcat(X::AbstractSparseVector{Tv,Ti}...) where {Tv,Ti}
    # check sizes
    n = length(X)
    tnnz = 0
    for j = 1:n
        tnnz += nnz(X[j])
    end

    # construction
    rnzind = Vector{Ti}(undef, tnnz)
    rnzval = Vector{Tv}(undef, tnnz)
    ir = 0
    len = 0
    @inbounds for j = 1:n
        xj = X[j]
        xnzind = nonzeroinds(xj)
        xnzval = nonzeros(xj)
        xnnz = length(xnzind)
        for i = 1:xnnz
            rnzind[ir + i] = xnzind[i] + len
        end
        copyto!(rnzval, ir+1, xnzval)
        ir += xnnz
        len += length(xj)
    end
    SparseVector(len, rnzind, rnzval)
end

hcat(Xin::Union{Vector, AbstractSparseVector}...) = hcat(map(sparse, Xin)...)
vcat(Xin::Union{Vector, AbstractSparseVector}...) = vcat(map(sparse, Xin)...)
# Without the following method, vertical concatenations of SparseVectors with Vectors
# fall back to the vertical concatenation method that ensures that combinations of
# sparse/special/dense matrix/vector types concatenate to SparseMatrixCSCs (because
# the vcat method immediately above is less specific, being defined in AbstractSparseVector
# rather than SparseVector).
vcat(X::Union{Vector,AbstractCompressedVector}...) = vcat(map(sparse, X)...)


### Concatenation of un/annotated sparse/special/dense vectors/matrices

const _SparseArrays = Union{SparseVector, AbstractSparseMatrixCSC, Adjoint{<:Any,<:SparseVector}, Transpose{<:Any,<:SparseVector}}
const _SparseConcatArrays = Union{_SpecialArrays, _SparseArrays}

const _Symmetric_SparseConcatArrays{T,A<:_SparseConcatArrays} = Symmetric{T,A}
const _Hermitian_SparseConcatArrays{T,A<:_SparseConcatArrays} = Hermitian{T,A}
const _Triangular_SparseConcatArrays{T,A<:_SparseConcatArrays} = LinearAlgebra.AbstractTriangular{T,A}
const _Annotated_SparseConcatArrays = Union{_Triangular_SparseConcatArrays, _Symmetric_SparseConcatArrays, _Hermitian_SparseConcatArrays}
# It's important that _SparseConcatGroup is a larger union than _DenseConcatGroup to make
# sparse cat-methods less specific and to kick in only if there is some sparse array present
const _SparseConcatGroup = Union{_DenseConcatGroup, _SparseConcatArrays, _Annotated_SparseConcatArrays}

# Concatenations involving un/annotated sparse/special matrices/vectors should yield sparse arrays

# the output array type is determined by the first element of the to be concatenated objects
# if this is a Number, the output would be dense by the fallback abstractarray.jl code (see cat_similar)
# so make sure that if that happens, the "array" is sparse (if more sparse arrays are involved, of course)
_sparse(x::Number) = sparsevec([1], [x], 1)
_sparse(A) = _makesparse(A)
_makesparse(x::Number) = x
_makesparse(x::AbstractVector) = convert(SparseVector, issparse(x) ? x : sparse(x))::SparseVector
_makesparse(x::AbstractMatrix) = convert(SparseMatrixCSC, issparse(x) ? x : sparse(x))::SparseMatrixCSC

# `@constprop :aggressive` allows `dims` to be propagated as constant improving return type inference
Base.@constprop :aggressive function Base._cat(dims, Xin::_SparseConcatGroup...)
    X = (_sparse(first(Xin)), map(_makesparse, Base.tail(Xin))...)
    T = promote_eltype(Xin...)
    return Base._cat_t(dims, T, X...)
end
function hcat(Xin::_SparseConcatGroup...)
    X = (_sparse(first(Xin)), map(_makesparse, Base.tail(Xin))...)
    return cat(X..., dims=Val(2))
end
function vcat(Xin::_SparseConcatGroup...)
    X = (_sparse(first(Xin)), map(_makesparse, Base.tail(Xin))...)
    return cat(X..., dims=Val(1))
end
hvcat(rows::Tuple{Vararg{Int}}, X::_SparseConcatGroup...) =
    vcat(_hvcat_rows(rows, X...)...)
function _hvcat_rows((row1, rows...)::Tuple{Vararg{Int}}, X::_SparseConcatGroup...)
    if row1 ≤ 0
        throw(ArgumentError("length of block row must be positive, got $row1"))
    end
    # assert `X` is non-empty so that inference of `eltype` won't include `Type{Union{}}`
    T = eltype(X::Tuple{Any,Vararg{Any}})
    # inference of `getindex` may be imprecise in case `row1` is not const-propagated up
    # to here, so help inference with the following type-assertions
    return (
        hcat(X[1 : row1]::Tuple{typeof(X[1]),Vararg{T}}...),
        _hvcat_rows(rows, X[row1+1:end]::Tuple{Vararg{T}}...)...
    )
end
_hvcat_rows(::Tuple{}, X::_SparseConcatGroup...) = ()

# make sure UniformScaling objects are converted to sparse matrices for concatenation
promote_to_array_type(A::Tuple{Vararg{Union{_SparseConcatGroup,UniformScaling}}}) = SparseMatrixCSC
promote_to_arrays_(n::Int, ::Type{SparseMatrixCSC}, J::UniformScaling) = sparse(J, n, n)

"""
    sparse_hcat(A...)

Concatenate along dimension 2. Return a SparseMatrixCSC object.

!!! compat "Julia 1.8"
    This method was added in Julia 1.8. It mimicks previous concatenation behavior, where
    the concatenation with specialized "sparse" matrix types from LinearAlgebra.jl
    automatically yielded sparse output even in the absence of any SparseArray argument.
"""
sparse_hcat(Xin::Union{AbstractVecOrMat,Number}...) = cat(_sparse(first(Xin)), map(_makesparse, Base.tail(Xin))..., dims=Val(2))
function sparse_hcat(X::Union{AbstractVecOrMat,UniformScaling,Number}...)
    LinearAlgebra._hcat(_sparse(first(X)), map(_makesparse, Base.tail(X))...; array_type = SparseMatrixCSC)
end

"""
    sparse_vcat(A...)

Concatenate along dimension 1. Return a SparseMatrixCSC object.

!!! compat "Julia 1.8"
    This method was added in Julia 1.8. It mimicks previous concatenation behavior, where
    the concatenation with specialized "sparse" matrix types from LinearAlgebra.jl
    automatically yielded sparse output even in the absence of any SparseArray argument.
"""
sparse_vcat(Xin::Union{AbstractVecOrMat,Number}...) = cat(_sparse(first(Xin)), map(_makesparse, Base.tail(Xin))..., dims=Val(1))
function sparse_vcat(X::Union{AbstractVecOrMat,UniformScaling,Number}...)
    LinearAlgebra._vcat(_sparse(first(X)), map(_makesparse, Base.tail(X))...; array_type = SparseMatrixCSC)
end

"""
    sparse_hvcat(rows::Tuple{Vararg{Int}}, values...)

Sparse horizontal and vertical concatenation in one call. This function is called
for block matrix syntax. The first argument specifies the number of
arguments to concatenate in each block row.

!!! compat "Julia 1.8"
    This method was added in Julia 1.8. It mimicks previous concatenation behavior, where
    the concatenation with specialized "sparse" matrix types from LinearAlgebra.jl
    automatically yielded sparse output even in the absence of any SparseArray argument.
"""
function sparse_hvcat(rows::Tuple{Vararg{Int}}, Xin::Union{AbstractVecOrMat,Number}...)
    hvcat(rows, _sparse(first(Xin)), map(_makesparse, Base.tail(Xin))...)
end
function sparse_hvcat(rows::Tuple{Vararg{Int}}, X::Union{AbstractVecOrMat,UniformScaling,Number}...)
    LinearAlgebra._hvcat(rows, _sparse(first(X)), map(_makesparse, Base.tail(X))...; array_type = SparseMatrixCSC)
end

### math functions

### Unary Map

# zero-preserving functions (z->z, nz->nz)
-(x::SparseVector) = SparseVector(length(x), copy(nonzeroinds(x)), -nonzeros(x))

for QT in (:LinAlgLeftQs, :LQPackedQ)
    @eval (*)(Q::$QT, B::AbstractSparseVector) = Q * Vector(B)
    @eval (*)(Q::AdjQType{<:Any,<:$QT}, B::AbstractSparseVector) = Q * Vector(B)

    @eval (*)(A::AbstractSparseVector, Q::$QT) = Vector(A) * Q
    @eval (*)(A::AbstractSparseVector, Q::AdjQType{<:Any,<:$QT}) = Vector(A) * Q
end

# functions f, such that
#   f(x) can be zero or non-zero when x != 0
#   f(x) = 0 when x == 0
#
macro unarymap_nz2z_z2z(op, TF)
    esc(quote
        function $(op)(x::AbstractSparseVector{Tv,Ti}) where Tv<:$(TF) where Ti<:Integer
            require_one_based_indexing(x)
            R = typeof($(op)(zero(Tv)))
            xnzind = nonzeroinds(x)
            xnzval = nonzeros(x)
            m = length(xnzind)

            ynzind = Vector{Ti}(undef, m)
            ynzval = Vector{R}(undef, m)
            ir = 0
            @inbounds for j = 1:m
                i = xnzind[j]
                v = $(op)(xnzval[j])
                if _isnotzero(v)
                    ir += 1
                    ynzind[ir] = i
                    ynzval[ir] = v
                end
            end
            resize!(ynzind, ir)
            resize!(ynzval, ir)
            SparseVector(length(x), ynzind, ynzval)
        end
    end)
end

# the rest of real, conj, imag are handled correctly via AbstractArray methods
@unarymap_nz2z_z2z real Complex
conj(x::AbstractCompressedVector{<:Complex}) = typeof(x)(length(x), copy(nonzeroinds(x)), conj(nonzeros(x)))
imag(x::AbstractSparseVector{Tv,Ti}) where {Tv<:Real,Ti<:Integer} = SparseVector(length(x), Ti[], Tv[])
@unarymap_nz2z_z2z imag Complex

# function that does not preserve zeros

macro unarymap_z2nz(op, TF)
    esc(quote
        function $(op)(x::AbstractSparseVector{Tv,<:Integer}) where Tv<:$(TF)
            require_one_based_indexing(x)
            v0 = $(op)(zero(Tv))
            R = typeof(v0)
            xnzind = nonzeroinds(x)
            xnzval = nonzeros(x)
            n = length(x)
            m = length(xnzind)
            y = fill(v0, n)
            @inbounds for j = 1:m
                y[xnzind[j]] = $(op)(xnzval[j])
            end
            y
        end
    end)
end

### Binary Map

# mode:
# 0: f(nz, nz) -> nz, f(z, nz) -> z, f(nz, z) ->  z
# 1: f(nz, nz) -> z/nz, f(z, nz) -> nz, f(nz, z) -> nz
# 2: f(nz, nz) -> z/nz, f(z, nz) -> z/nz, f(nz, z) -> z/nz

function _binarymap(f::Function,
                    x::AbstractSparseVector{Tx},
                    y::AbstractSparseVector{Ty},
                    mode::Int) where {Tx,Ty}
    0 <= mode <= 2 || throw(ArgumentError("Incorrect mode $mode."))
    R = Base.Broadcast.combine_eltypes(f, (x, y))
    n = length(x)
    length(y) == n || throw(DimensionMismatch())

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    ynzind = nonzeroinds(y)
    ynzval = nonzeros(y)
    mx = length(xnzind)
    my = length(ynzind)
    cap = (mode == 0 ? min(mx, my) : mx + my)::Int

    rind = Vector{Int}(undef, cap)
    rval = Vector{R}(undef, cap)
    ir = 0
    ir = (
        mode == 0 ? _binarymap_mode_0!(f, mx, my,
            xnzind, xnzval, ynzind, ynzval, rind, rval) :
        mode == 1 ? _binarymap_mode_1!(f, mx, my,
            xnzind, xnzval, ynzind, ynzval, rind, rval) :
        _binarymap_mode_2!(f, mx, my,
            xnzind, xnzval, ynzind, ynzval, rind, rval)
    )::Int

    resize!(rind, ir)
    resize!(rval, ir)
    return SparseVector(n, rind, rval)
end

function _binarymap_mode_0!(f::Function, mx::Int, my::Int,
                            xnzind, xnzval, ynzind, ynzval, rind, rval)
    # f(nz, nz) -> nz, f(z, nz) -> z, f(nz, z) ->  z
    require_one_based_indexing(xnzind, ynzind, xnzval, ynzval, rind, rval)
    ir = 0; ix = 1; iy = 1
    @inbounds while ix <= mx && iy <= my
        jx = xnzind[ix]
        jy = ynzind[iy]
        if jx == jy
            v = f(xnzval[ix], ynzval[iy])
            ir += 1; rind[ir] = jx; rval[ir] = v
            ix += 1; iy += 1
        elseif jx < jy
            ix += 1
        else
            iy += 1
        end
    end
    return ir
end

function _binarymap_mode_1!(f::Function, mx::Int, my::Int,
                            xnzind, xnzval::AbstractVector{Tx},
                            ynzind, ynzval::AbstractVector{Ty},
                            rind, rval) where {Tx,Ty}
    # f(nz, nz) -> z/nz, f(z, nz) -> nz, f(nz, z) -> nz
    require_one_based_indexing(xnzind, ynzind, xnzval, ynzval, rind, rval)
    ir = 0; ix = 1; iy = 1
    @inbounds while ix <= mx && iy <= my
        jx = xnzind[ix]
        jy = ynzind[iy]
        if jx == jy
            v = f(xnzval[ix], ynzval[iy])
            if _isnotzero(v)
                ir += 1; rind[ir] = jx; rval[ir] = v
            end
            ix += 1; iy += 1
        elseif jx < jy
            v = f(xnzval[ix], zero(Ty))
            ir += 1; rind[ir] = jx; rval[ir] = v
            ix += 1
        else
            v = f(zero(Tx), ynzval[iy])
            ir += 1; rind[ir] = jy; rval[ir] = v
            iy += 1
        end
    end
    @inbounds while ix <= mx
        v = f(xnzval[ix], zero(Ty))
        ir += 1; rind[ir] = xnzind[ix]; rval[ir] = v
        ix += 1
    end
    @inbounds while iy <= my
        v = f(zero(Tx), ynzval[iy])
        ir += 1; rind[ir] = ynzind[iy]; rval[ir] = v
        iy += 1
    end
    return ir
end

function _binarymap_mode_2!(f::Function, mx::Int, my::Int,
                            xnzind, xnzval::AbstractVector{Tx},
                            ynzind, ynzval::AbstractVector{Ty},
                            rind, rval) where {Tx,Ty}
    # f(nz, nz) -> z/nz, f(z, nz) -> z/nz, f(nz, z) -> z/nz
    require_one_based_indexing(xnzind, ynzind, xnzval, ynzval, rind, rval)
    ir = 0; ix = 1; iy = 1
    @inbounds while ix <= mx && iy <= my
        jx = xnzind[ix]
        jy = ynzind[iy]
        if jx == jy
            v = f(xnzval[ix], ynzval[iy])
            if _isnotzero(v)
                ir += 1; rind[ir] = jx; rval[ir] = v
            end
            ix += 1; iy += 1
        elseif jx < jy
            v = f(xnzval[ix], zero(Ty))
            if _isnotzero(v)
                ir += 1; rind[ir] = jx; rval[ir] = v
            end
            ix += 1
        else
            v = f(zero(Tx), ynzval[iy])
            if _isnotzero(v)
                ir += 1; rind[ir] = jy; rval[ir] = v
            end
            iy += 1
        end
    end
    @inbounds while ix <= mx
        v = f(xnzval[ix], zero(Ty))
        if _isnotzero(v)
            ir += 1; rind[ir] = xnzind[ix]; rval[ir] = v
        end
        ix += 1
    end
    @inbounds while iy <= my
        v = f(zero(Tx), ynzval[iy])
        if _isnotzero(v)
            ir += 1; rind[ir] = ynzind[iy]; rval[ir] = v
        end
        iy += 1
    end
    return ir
end

# definition of a few known broadcasted/mapped binary functions — all others defer to HigherOrderFunctions

_bcast_binary_map(f, x, y, mode) = length(x) == length(y) ? _binarymap(f, x, y, mode) : HigherOrderFns._diffshape_broadcast(f, x, y)
_getmode(::typeof(+), ::Type, ::Type) = 1
_getmode(::typeof(-), ::Type, ::Type) = 1
_getmode(::typeof(*), ::Type, ::Type) = 0
_getmode(::typeof(*), ::Type{Union{Missing, T}}, ::Type) where {T} = 2
_getmode(::typeof(*), ::Type, ::Type{Union{Missing, T}}) where {T} = 2
_getmode(::typeof(*), ::Type{Union{Missing, T}}, ::Type{Union{Missing, S}}) where {T,S} = 2
_getmode(::typeof(min), ::Type, ::Type) = 2
_getmode(::typeof(max), ::Type, ::Type) = 2
for (fun, mode) in [(:+, 1), (:-, 1), (:*, 0), (:min, 2), (:max, 2)]
    fun in (:+, :-) && @eval begin
        # Addition and subtraction can be defined directly on the arrays (without map/broadcast)
        $(fun)(x::AbstractSparseVector, y::AbstractSparseVector) = _binarymap($(fun), x, y, $mode)
    end
    @eval begin
        map(::typeof($fun), x::AbstractSparseVector{Tx}, y::AbstractSparseVector{Ty}) where {Tx, Ty} =
            _binarymap($fun, x, y, _getmode($fun, Tx, Ty))
        map(::typeof($fun), x::AbstractCompressedVector{Tx}, y::AbstractCompressedVector{Ty}) where {Tx, Ty} =
            _binarymap($fun, x, y, _getmode($fun, Tx, Ty))
        broadcast(::typeof($fun), x::AbstractSparseVector{Tx}, y::AbstractSparseVector{Ty}) where {Tx, Ty} =
            _bcast_binary_map($fun, x, y, _getmode($fun, Tx, Ty))
        broadcast(::typeof($fun), x::AbstractCompressedVector{Tx}, y::AbstractCompressedVector{Ty}) where {Tx, Ty} =
            _bcast_binary_map($fun, x, y, _getmode($fun, Tx, Ty))
    end
end

### Reduction
Base.reducedim_initarray(A::SparseVectorUnion, region, v0, ::Type{R}) where {R} =
    fill!(Array{R}(undef, Base.to_shape(Base.reduced_indices(A, region))), v0)

function Base._mapreduce(f, op, ::IndexCartesian, A::SparseVectorUnion{T}) where {T}
    isempty(A) && return Base.mapreduce_empty(f, op, T)
    z = nnz(A)
    rest, ini = if z == 0
        length(A)-z-1, f(zero(T))
    else
        length(A)-z, Base.mapreduce_impl(f, op, nonzeros(A), 1, z)
    end
    _mapreducezeros(f, op, T, rest, ini)
end

Base._any(f, A::SparseVectorUnion, ::Colon) =
    iszero(length(A)) ? false : Base._mapreduce(f, |, IndexCartesian(), A)
Base._all(f, A::SparseVectorUnion, ::Colon) =
    iszero(length(A)) ? true  : Base._mapreduce(f, &, IndexCartesian(), A)

function Base.mapreducedim!(f, op, R::AbstractVector, A::SparseVectorUnion)
    # dim1 reduction could be safely replaced with a mapreduce
    if length(R) == 1
        I = firstindex(R)
        v = Base._mapreduce(f, op, IndexCartesian(), A)
        R[I] = op(R[I], v)
        return R
    end
    # otherwise there's no reduction
    map!((x, y) -> op(x, f(y)), R, R, A)
end

for (fun, comp, word) in ((:findmin, :(<), "minimum"), (:findmax, :(>), "maximum"))
    @eval function $fun(f, x::AbstractSparseVector{T}) where {T}
        n = length(x)
        n > 0 || throw(ArgumentError($word * " over empty array is not allowed"))
        nzvals = nonzeros(x)
        m = length(nzvals)
        m == 0 && return zero(T), firstindex(x)
        val, index = $fun(f, nzvals)
        m == n && return val, index
        nzinds = nonzeroinds(x)
        zeroval = f(zero(T))
        $comp(val, zeroval) && return val, nzinds[index]
        # we need to find the first zero, which could be stored or implicit
        # we try to avoid findfirst(iszero, x)
        sindex = findfirst(_iszero, nzvals) # first stored zero, if any
        zindex = findfirst(i -> i < nzinds[i], eachindex(nzinds)) # first non-stored zero
        index = if isnothing(sindex)
            # non-stored zero are contiguous and at the end
            isnothing(zindex) && last(nzinds) < lastindex(x) ? last(nzinds) + 1 : zindex
        else
            min(sindex, zindex)
        end
        return zeroval, index
    end
end

norm(x::SparseVectorUnion, p::Real=2) = norm(nonzeros(x), p)

### linalg.jl

# Transpose
# (The only sparse matrix structure in base is CSC, so a one-row sparse matrix is worse than dense)
transpose(sv::AbstractCompressedVector) = Transpose(sv)
adjoint(sv::AbstractCompressedVector) = Adjoint(sv)

### BLAS Level-1

# axpy

function LinearAlgebra.axpy!(a::Number, x::SparseVectorUnion, y::AbstractVector)
    require_one_based_indexing(x, y)
    length(x) == length(y) || throw(DimensionMismatch())
    nzind = nonzeroinds(x)
    nzval = nonzeros(x)
    m = length(nzind)

    if a == oneunit(a)
        for i = 1:m
            @inbounds ii = nzind[i]
            @inbounds v = nzval[i]
            y[ii] += v
        end
    elseif a == -oneunit(a)
        for i = 1:m
            @inbounds ii = nzind[i]
            @inbounds v = nzval[i]
            y[ii] -= v
        end
    else
        for i = 1:m
            @inbounds ii = nzind[i]
            @inbounds v = nzval[i]
            y[ii] += a * v
        end
    end
    return y
end


# scaling

function rmul!(x::SparseVectorUnion, a::Real)
    rmul!(nonzeros(x), a)
    return x
end
function rmul!(x::SparseVectorUnion, a::Complex)
    rmul!(nonzeros(x), a)
    return x
end
function lmul!(a::Real, x::SparseVectorUnion)
    rmul!(nonzeros(x), a)
    return x
end
function lmul!(a::Complex, x::SparseVectorUnion)
    rmul!(nonzeros(x), a)
    return x
end

(*)(x::SparseVectorUnion, a::Number) =
    @if_move_fixed x SparseVector(length(x), copy(nonzeroinds(x)), nonzeros(x) * a)
(*)(a::Number, x::SparseVectorUnion) =
    @if_move_fixed x SparseVector(length(x), copy(nonzeroinds(x)), a * nonzeros(x))
(/)(x::SparseVectorUnion, a::Number) =
    @if_move_fixed x SparseVector(length(x), copy(nonzeroinds(x)), nonzeros(x) / a)
# dot
function dot(x::AbstractVector{Tx}, y::SparseVectorUnion{Ty}) where {Tx<:Number,Ty<:Number}
    require_one_based_indexing(x, y)
    n = length(x)
    length(y) == n || throw(DimensionMismatch())
    nzind = nonzeroinds(y)
    nzval = nonzeros(y)
    s = dot(zero(Tx), zero(Ty))
    @inbounds for i = 1:length(nzind)
        s += dot(x[nzind[i]], nzval[i])
    end
    return s
end

function dot(x::SparseVectorUnion{Tx}, y::AbstractVector{Ty}) where {Tx<:Number,Ty<:Number}
    require_one_based_indexing(x, y)
    n = length(y)
    length(x) == n || throw(DimensionMismatch())
    nzind = nonzeroinds(x)
    nzval = nonzeros(x)
    s = dot(zero(Tx), zero(Ty))
    @inbounds for i = 1:length(nzind)
        s += dot(nzval[i], y[nzind[i]])
    end
    return s
end

function _spdot(f::Function,
                xj::Int, xj_last::Int, xnzind, xnzval,
                yj::Int, yj_last::Int, ynzind, ynzval)
    # dot product between ranges of non-zeros,
    s = f(zero(eltype(xnzval)), zero(eltype(ynzval)))
    @inbounds while xj <= xj_last && yj <= yj_last
        ix = xnzind[xj]
        iy = ynzind[yj]
        if ix == iy
            s += f(xnzval[xj], ynzval[yj])
            xj += 1
            yj += 1
        elseif ix < iy
            xj += 1
        else
            yj += 1
        end
    end
    s
end

function dot(x::SparseVectorUnion{<:Number}, y::SparseVectorUnion{<:Number})
    x === y && return sum(abs2, x)
    n = length(x)
    length(y) == n || throw(DimensionMismatch())

    xnzind = nonzeroinds(x)
    ynzind = nonzeroinds(y)
    xnzval = nonzeros(x)
    ynzval = nonzeros(y)

    _spdot(dot,
           1, length(xnzind), xnzind, xnzval,
           1, length(ynzind), ynzind, ynzval)
end


### BLAS-2 / dense A * sparse x -> dense y

# lowrankupdate (BLAS.ger! like)
function LinearAlgebra.lowrankupdate!(A::StridedMatrix, x::AbstractVector, y::SparseVectorUnion, α::Number = 1)
    require_one_based_indexing(A, x, y)
    nzi = nonzeroinds(y)
    nzv = nonzeros(y)
    @inbounds for (j,v) in zip(nzi,nzv)
        αv = α*conj(v)
        for i in axes(x, 1)
            A[i,j] += x[i]*αv
        end
    end
    return A
end

# * and mul!

const _StridedOrTriangularMatrix{T} = Union{StridedMatrix{T}, LowerTriangular{T}, UnitLowerTriangular{T}, UpperTriangular{T}, UnitUpperTriangular{T}}

function (*)(A::_StridedOrTriangularMatrix{Ta}, x::AbstractSparseVector{Tx}) where {Ta,Tx}
    require_one_based_indexing(A, x)
    m, n = size(A)
    length(x) == n || throw(DimensionMismatch())
    Ty = promote_op(matprod, eltype(A), eltype(x))
    y = Vector{Ty}(undef, m)
    mul!(y, A, x)
end

function mul!(y::AbstractVector, A::_StridedOrTriangularMatrix, x::AbstractSparseVector, α::Number, β::Number)
    require_one_based_indexing(y, A, x)
    m, n = size(A)
    length(x) == n && length(y) == m || throw(DimensionMismatch())
    m == 0 && return y
    if β != one(β)
        β == zero(β) ? fill!(y, zero(eltype(y))) : rmul!(y, β)
    end
    α == zero(α) && return y

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    @inbounds for i = 1:length(xnzind)
        v = xnzval[i]
        if _isnotzero(v)
            j = xnzind[i]
            αv = v * α
            for r = 1:m
                y[r] += A[r,j] * αv
            end
        end
    end
    return y
end

# * and mul!(C, transpose(A), B)

function *(tA::Transpose{<:Any,<:_StridedOrTriangularMatrix{Ta}}, x::AbstractSparseVector{Tx}) where {Ta,Tx}
    require_one_based_indexing(tA, x)
    m, n = size(tA)
    length(x) == n || throw(DimensionMismatch())
    Ty = promote_op(matprod, eltype(tA), eltype(x))
    y = Vector{Ty}(undef, m)
    mul!(y, tA, x)
end

function mul!(y::AbstractVector, tA::Transpose{<:Any,<:_StridedOrTriangularMatrix}, x::AbstractSparseVector, α::Number, β::Number)
    require_one_based_indexing(y, tA, x)
    m, n = size(tA)
    length(x) == n && length(y) == m || throw(DimensionMismatch())
    m == 0 && return y
    if β != one(β)
        β == zero(β) ? fill!(y, zero(eltype(y))) : rmul!(y, β)
    end
    α == zero(α) && return y

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    _nnz = length(xnzind)
    _nnz == 0 && return y

    A = tA.parent
    Ty = promote_op(matprod, eltype(A), eltype(x))
    @inbounds for j = 1:m
        s = zero(Ty)
        for i = 1:_nnz
            s += transpose(A[xnzind[i], j]) * xnzval[i]
        end
        y[j] += s * α
    end
    return y
end

# * and mul!(C, adjoint(A), B)

function *(adjA::Adjoint{<:Any,<:_StridedOrTriangularMatrix{Ta}}, x::AbstractSparseVector{Tx}) where {Ta,Tx}
    require_one_based_indexing(adjA, x)
    m, n = size(adjA)
    length(x) == n || throw(DimensionMismatch())
    Ty = promote_op(matprod, eltype(adjA), eltype(x))
    y = Vector{Ty}(undef, m)
    mul!(y, adjA, x)
end

function mul!(y::AbstractVector, adjA::Adjoint{<:Any,<:_StridedOrTriangularMatrix}, x::AbstractSparseVector, α::Number, β::Number)
    require_one_based_indexing(y, adjA, x)
    m, n = size(adjA)
    length(x) == n && length(y) == m || throw(DimensionMismatch())
    m == 0 && return y
    if β != one(β)
        β == zero(β) ? fill!(y, zero(eltype(y))) : rmul!(y, β)
    end
    α == zero(α) && return y

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    _nnz = length(xnzind)
    _nnz == 0 && return y

    A = adjA.parent
    Ty = promote_op(matprod, eltype(A), eltype(x))
    @inbounds for j = 1:m
        s = zero(Ty)
        for i = 1:_nnz
            s += adjoint(A[xnzind[i], j]) * xnzval[i]
        end
        y[j] += s * α
    end
    return y
end


### BLAS-2 / sparse A * sparse x -> dense y

function densemv(A::AbstractSparseMatrixCSC, x::AbstractSparseVector; trans::AbstractChar='N')
    local xlen::Int, ylen::Int
    require_one_based_indexing(A, x)
    m, n = size(A)
    if trans == 'N' || trans == 'n'
        xlen = n; ylen = m
    elseif trans == 'T' || trans == 't' || trans == 'C' || trans == 'c'
        xlen = m; ylen = n
    else
        throw(ArgumentError("Invalid trans character $trans"))
    end
    xlen == length(x) || throw(DimensionMismatch())
    T = promote_op(matprod, eltype(A), eltype(x))
    y = Vector{T}(undef, ylen)
    if trans == 'N' || trans == 'n'
        mul!(y, A, x)
    elseif trans == 'T' || trans == 't'
        mul!(y, transpose(A), x)
    else # trans == 'C' || trans == 'c'
        mul!(y, adjoint(A), x)
    end
    y
end

# * and mul!

function mul!(y::AbstractVector, A::AbstractSparseMatrixCSC, x::AbstractSparseVector, α::Number, β::Number)
    require_one_based_indexing(y, A, x)
    m, n = size(A)
    length(x) == n && length(y) == m || throw(DimensionMismatch())
    m == 0 && return y
    if β != one(β)
        β == zero(β) ? fill!(y, zero(eltype(y))) : rmul!(y, β)
    end
    α == zero(α) && return y

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    Acolptr = getcolptr(A)
    Arowval = rowvals(A)
    Anzval = nonzeros(A)

    @inbounds for i = 1:length(xnzind)
        v = xnzval[i]
        if _isnotzero(v)
            αv = v * α
            j = xnzind[i]
            for r = Acolptr[j]:(Acolptr[j+1]-1)
                y[Arowval[r]] += Anzval[r] * αv
            end
        end
    end
    return y
end

# * and *(Tranpose(A), B)
mul!(y::AbstractVector, tA::Transpose{<:Any,<:AbstractSparseMatrixCSC}, x::AbstractSparseVector, α::Number, β::Number) =
    _At_or_Ac_mul_B!((a,b) -> transpose(a) * b, y, tA.parent, x, α, β)

mul!(y::AbstractVector, adjA::Adjoint{<:Any,<:AbstractSparseMatrixCSC}, x::AbstractSparseVector, α::Number, β::Number) =
    _At_or_Ac_mul_B!((a,b) -> adjoint(a) * b, y, adjA.parent, x, α, β)

function _At_or_Ac_mul_B!(tfun::Function,
                          y::AbstractVector, A::AbstractSparseMatrixCSC, x::AbstractSparseVector,
                          α::Number, β::Number)
    require_one_based_indexing(y, A, x)
    m, n = size(A)
    length(x) == m && length(y) == n || throw(DimensionMismatch())
    n == 0 && return y
    if β != one(β)
        β == zero(β) ? fill!(y, zero(eltype(y))) : rmul!(y, β)
    end
    α == zero(α) && return y

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    Acolptr = getcolptr(A)
    Arowval = rowvals(A)
    Anzval = nonzeros(A)
    mx = length(xnzind)

    for j = 1:n
        # s <- dot(A[:,j], x)
        s = _spdot(tfun, Acolptr[j], Acolptr[j+1]-1, Arowval, Anzval,
                   1, mx, xnzind, xnzval)
        @inbounds y[j] += s * α
    end
    return y
end


### BLAS-2 / sparse A * sparse x -> dense y

function *(A::AbstractSparseMatrixCSC, x::AbstractSparseVector)
    require_one_based_indexing(A, x)
    y = densemv(A, x)
    initcap = min(nnz(A), size(A,1))
    _dense2sparsevec(y, initcap)
end

*(tA::Transpose{<:Any,<:AbstractSparseMatrixCSC}, x::AbstractSparseVector) =
    _At_or_Ac_mul_B((a,b) -> transpose(a) * b, tA.parent, x, promote_op(matprod, eltype(tA), eltype(x)))

*(adjA::Adjoint{<:Any,<:AbstractSparseMatrixCSC}, x::AbstractSparseVector) =
    _At_or_Ac_mul_B((a,b) -> adjoint(a) * b, adjA.parent, x, promote_op(matprod, eltype(adjA), eltype(x)))

function _At_or_Ac_mul_B(tfun::Function, A::AbstractSparseMatrixCSC{TvA,TiA}, x::AbstractSparseVector{TvX,TiX},
                         Tv = promote_op(matprod, TvA, TvX)) where {TvA,TiA,TvX,TiX}
    require_one_based_indexing(A, x)
    m, n = size(A)
    length(x) == m || throw(DimensionMismatch())
    Ti = promote_type(TiA, TiX)

    xnzind = nonzeroinds(x)
    xnzval = nonzeros(x)
    Acolptr = getcolptr(A)
    Arowval = rowvals(A)
    Anzval = nonzeros(A)
    mx = length(xnzind)

    ynzind = Vector{Ti}(undef, n)
    ynzval = Vector{Tv}(undef, n)

    jr = 0
    for j = 1:n
        s = _spdot(tfun, Acolptr[j], Acolptr[j+1]-1, Arowval, Anzval,
                   1, mx, xnzind, xnzval)
        if s != zero(s)
            jr += 1
            ynzind[jr] = j
            ynzval[jr] = s
        end
    end
    if jr < n
        resize!(ynzind, jr)
        resize!(ynzval, jr)
    end
    return @if_move_fixed A x SparseVector(n, ynzind, ynzval)
end


# define matrix division operations involving triangular matrices and sparse vectors
# the valid left-division operations are A[t|c]_ldiv_B[!] and \
# the valid right-division operations are A(t|c)_rdiv_B[t|c][!]
# see issue #14005 for discussion of these methods
for isunittri in (true, false), islowertri in (true, false)
    unitstr = isunittri ? "Unit" : ""
    halfstr = islowertri ? "Lower" : "Upper"
    tritype = :(LinearAlgebra.$(Symbol(unitstr, halfstr, "Triangular")))

    # build out-of-place left-division operations
    # broad method where elements are Numbers
    @eval function \(A::$tritype{<:TA,<:AbstractMatrix}, b::AbstractCompressedVector{Tb}) where {TA<:Number,Tb<:Number}
        TAb = $(isunittri ?
            :(typeof(zero(TA)*zero(Tb) + zero(TA)*zero(Tb))) :
            :(typeof((zero(TA)*zero(Tb) + zero(TA)*zero(Tb))/one(TA))) )
        return LinearAlgebra.ldiv!(convert(AbstractArray{TAb}, A), convert(Array{TAb}, b))
    end
    # fallback where elements are not Numbers
    @eval \(A::$tritype, b::AbstractCompressedVector) = LinearAlgebra.ldiv!(A, copy(b))

    # faster method requiring good view support of the
    # triangular matrix type. hence the StridedMatrix restriction.
    for (istrans, applyxform, xformtype, xformop) in (
            (false, false, :identity,  :identity),
            (true,  true,  :Transpose, :transpose),
            (true,  true,  :Adjoint,   :adjoint) )

        xformtritype = applyxform ? :($tritype{<:TA,<:$xformtype{<:Any,<:StridedMatrix}}) :
                                    :($tritype{<:TA,<:StridedMatrix})
        @eval function \(xA::$xformtritype, b::AbstractCompressedVector{Tb}) where {TA<:Number,Tb<:Number}
            TAb = $( isunittri ?
                :(typeof(zero(TA)*zero(Tb) + zero(TA)*zero(Tb))) :
                :(typeof((zero(TA)*zero(Tb) + zero(TA)*zero(Tb))/one(TA))) )
            r = convert(Array{TAb}, b)
            # If b has no nonzero entries, then r is necessarily zero. If b has nonzero
            # entries, then the operation involves only b[nzrange], so we extract and
            # operate on solely b[nzrange] for efficiency.
            A = $( applyxform ? :(parent(parent(xA))) : :(parent(xA)) )
            if nnz(b) != 0
                nzrange = $( islowertri ?
                    :(nonzeroinds(b)[1]:length(b::AbstractCompressedVector)) :
                    :(1:nonzeroinds(b)[end]) )
                nzrangeviewr = view(r, nzrange)
                nzrangeviewA = $tritype($xformop(view(A, nzrange, nzrange)))
                LinearAlgebra.ldiv!(convert(AbstractArray{TAb}, nzrangeviewA), nzrangeviewr)
            end
            return r
        end

        # build in-place left-division operations
        xformtritype = applyxform ? :($tritype{<:Any,<:$xformtype{<:Any,<:StridedMatrix}}) :
                                    :($tritype{<:Any,<:StridedMatrix})

        # the generic in-place left-division methods handle these cases, but
        # we can achieve greater efficiency where the triangular matrix provides
        # good view support, hence the StridedMatrix restriction.
        @eval function ldiv!(xA::$xformtritype, b::AbstractCompressedVector)
            A = $( applyxform ? :(parent(parent(xA))) : :(parent(xA)) )
            # If b has no nonzero entries, the result is necessarily zero and this call
            # reduces to a no-op. If b has nonzero entries, then...
            if nnz(b) != 0
                # densify the relevant part of b in one shot rather
                # than potentially repeatedly reallocating during the solve
                $( islowertri ?
                    :(_densifyfirstnztoend!(b)) :
                    :(_densifystarttolastnz!(b)) )
                # this operation involves only the densified section, so
                # for efficiency we extract and operate on solely that section
                # furthermore we operate on that section as a dense vector
                # such that dispatch has a chance to exploit, e.g., tuned BLAS
                nzrange = $( islowertri ?
                    :(nonzeroinds(b)[1]:length(b)) :
                    :(1:nonzeroinds(b)[end]) )
                nzrangeviewbnz = view(nonzeros(b), nzrange .- (nonzeroinds(b)[1] - 1))
                nzrangeviewA = $tritype($xformop(view(A, nzrange, nzrange)))
                LinearAlgebra.ldiv!(nzrangeviewA, nzrangeviewbnz)
            end
            return b
        end
    end
end

# helper functions for in-place matrix division operations defined above
"Densifies `x::SparseVector` from its first nonzero (`x[nonzeroinds(x)[1]]`) through its end (`x[length(x::SparseVector)]`)."
function _densifyfirstnztoend!(x::SparseVector)
    # lengthen containers
    oldnnz = nnz(x)
    newnnz = length(x::SparseVector) - nonzeroinds(x)[1] + 1
    resize!(nonzeros(x), newnnz)
    resize!(nonzeroinds(x), newnnz)
    # redistribute nonzero values over lengthened container
    # initialize now-allocated zero values simultaneously
    nextpos = newnnz
    @inbounds for oldpos in oldnnz:-1:1
        nzi = nonzeroinds(x)[oldpos]
        nzv = nonzeros(x)[oldpos]
        newpos = nzi - nonzeroinds(x)[1] + 1
        newpos < nextpos && (nonzeros(x)[newpos+1:nextpos] .= 0)
        newpos == oldpos && break
        nonzeros(x)[newpos] = nzv
        nextpos = newpos - 1
    end
    # finally update lengthened nzinds
    nonzeroinds(x)[2:end] = (nonzeroinds(x)[1]+1):length(x::SparseVector)
    return x
end

"Densifies `x::SparseVector` from its beginning (`x[1]`) through its last nonzero (`x[nonzeroinds(x)[end]]`)."
function _densifystarttolastnz!(x::SparseVector)
    # lengthen containers
    oldnnz = nnz(x)
    newnnz = nonzeroinds(x)[end]
    resize!(nonzeros(x), newnnz)
    resize!(nonzeroinds(x), newnnz)
    # redistribute nonzero values over lengthened container
    # initialize now-allocated zero values simultaneously
    nextpos = newnnz
    @inbounds for oldpos in oldnnz:-1:1
        nzi = nonzeroinds(x)[oldpos]
        nzv = nonzeros(x)[oldpos]
        nzi < nextpos && (nonzeros(x)[nzi+1:nextpos] .= 0)
        nzi == oldpos && (nextpos = 0; break)
        nonzeros(x)[nzi] = nzv
        nextpos = nzi - 1
    end
    nextpos > 0 && (nonzeros(x)[1:nextpos] .= 0)
    # finally update lengthened nzinds
    nonzeroinds(x)[1:newnnz] = 1:newnnz
    x
end

#sorting
function sort!(x::AbstractCompressedVector; kws...)
    nz = nonzeros(x)
    sort!(nz; kws...)
    i = searchsortedfirst(nz, zero(eltype(x)); kws...)
    I = nonzeroinds(x)
    Base.require_one_based_indexing(x, nz, I)
    I[1:i-1] .= 1:i-1
    I[i:end] .= i+length(x)-length(nz):length(x)
    x
end

function fkeep!(f, x::AbstractCompressedVector{Tv}) where Tv
    if _is_fixed(x)
        for i in 1:nnz(x)
            if !f(nonzeroinds(x)[i], nonzeros(x)[i])
                nonzeros(x)[i] = zero(Tv)
            end
        end
    else
        nzind = nonzeroinds(x)
        nzval = nonzeros(x)

        x_writepos = 1
        @inbounds for xk in 1:nnz(x)
            xi = nzind[xk]
            xv = nzval[xk]
            # If this element should be kept, rewrite in new position
            if f(xi, xv)
                if x_writepos != xk
                    nzind[x_writepos] = xi
                    nzval[x_writepos] = xv
                end
                x_writepos += 1
            end
        end

        # Trim x's storage if necessary
        x_nnz = x_writepos - 1
        resize!(nzval, x_nnz)
        resize!(nzind, x_nnz)
    end
    return x
end



"""
    droptol!(x::AbstractCompressedVector, tol)

Removes stored values from `x` whose absolute value is less than or equal to `tol`.
"""
droptol!(x::AbstractCompressedVector, tol) = fkeep!((i, x) -> abs(x) > tol, x)

"""
    dropzeros!(x::AbstractCompressedVector)

Removes stored numerical zeros from `x`.

For an out-of-place version, see [`dropzeros`](@ref). For
algorithmic information, see `fkeep!`.
"""
dropzeros!(x::AbstractCompressedVector) = _is_fixed(x) ? x : fkeep!((i, x) -> _isnotzero(x), x)


"""
    dropzeros(x::AbstractCompressedVector)

Generates a copy of `x` and removes numerical zeros from that copy.

For an in-place version and algorithmic information, see [`dropzeros!`](@ref).

# Examples
```jldoctest
julia> A = sparsevec([1, 2, 3], [1.0, 0.0, 1.0])
3-element SparseVector{Float64, Int64} with 3 stored entries:
  [1]  =  1.0
  [2]  =  0.0
  [3]  =  1.0

julia> dropzeros(A)
3-element SparseVector{Float64, Int64} with 2 stored entries:
  [1]  =  1.0
  [3]  =  1.0
```
"""
dropzeros(x::AbstractCompressedVector) = dropzeros!(copy(x))

function copy!(dst::AbstractCompressedVector, src::AbstractCompressedVector)
    length(dst) == length(src) || throw(ArgumentError("Sparse vectors should have the same length for copy!"))
    copy!(nonzeros(dst), nonzeros(src))
    copy!(nonzeroinds(dst), nonzeroinds(src))
    return dst
end

function copy!(dst::AbstractCompressedVector, src::AbstractVector)
    length(dst) == length(src) || throw(ArgumentError("Sparse vector should have the same length as source for copy!"))
    _dense2indval!(nonzeroinds(dst), nonzeros(dst), src)
    return dst
end

function _fillnonzero!(arr::AbstractSparseMatrixCSC{Tv, Ti}, val) where {Tv,Ti}
    m, n = size(arr)
    resize!(getcolptr(arr), n+1)
    resize!(rowvals(arr), m*n)
    resize!(nonzeros(arr), m*n)
    copyto!(getcolptr(arr), 1:m:n*m+1)
    fill!(nonzeros(arr), val)
    index = 1
    @inbounds for _ in 1:n
        for i in 1:m
            rowvals(arr)[index] = Ti(i)
            index += 1
        end
    end
    arr
end

function _fillnonzero!(arr::AbstractCompressedVector{Tv,Ti}, val) where {Tv,Ti}
    n = length(arr)
    resize!(nonzeroinds(arr), n)
    resize!(nonzeros(arr), n)
    @inbounds for i in 1:n
        nonzeroinds(arr)[i] = Ti(i)
    end
    fill!(nonzeros(arr), val)
    arr
end

import Base.fill!
function fill!(A::Union{AbstractCompressedVector, AbstractSparseMatrixCSC}, x)
    T = eltype(A)
    xT = convert(T, x)
    if xT == zero(T)
        fill!(nonzeros(A), xT)
    else
        _fillnonzero!(A, xT)
    end
    return A
end

# in-place shifts a sparse subvector by r. Used also by sparsematrix.jl
function subvector_shifter!(R::AbstractVector, V::AbstractVector, start::Integer, fin::Integer, m::Integer, r::Integer)
    split = fin
    @inbounds for j = start:fin
        # shift positions ...
        R[j] += r
        if R[j] <= m
            split = j
        else
            R[j] -= m
        end
    end
    # ...but rowval should be sorted within columns
    circshift!(@view(R[start:fin]), -split+start-1)
    circshift!(@view(V[start:fin]), -split+start-1)
end

function circshift!(O::SparseVector, X::SparseVector, (r,)::Base.DimsInteger{1})
    copy!(O, X)
    subvector_shifter!(nonzeroinds(O), nonzeros(O), 1, length(nonzeroinds(O)), length(O), mod(r, length(X)))
    return O
end

circshift!(O::SparseVector, X::SparseVector, r::Real,) = circshift!(O, X, (Integer(r),))
