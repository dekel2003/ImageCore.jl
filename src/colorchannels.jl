# Implements two view types for "converting" between arrays-of-colors
# and arrays-of-numbers (with the "first dimension" corresponding to
# color channels)
#  - ChannelView: view a color array as if it were an array of numbers
#  - ColorView: view an array of numbers as if it were an array of colors
# Examples:
#    img is a m-by-n Array{RGB{Float32}}
#    ChannelView(img) is a 3-by-m-by-n AbstractArray{Float32}
#
#    buffer is a 3-by-m-by-n Array{N0f8}
#    ColorView{RGB}(buffer) is an m-by-n AbstractArray{RGB{N0f8}}

# "First dimension" applies to colors like RGB; by default, Gray
# images don't use a whole dimension (of size 1) just to encode
# colors. But it's easy to change that behavior with the flip of a
# switch:
const squeeze1 = true # when true, don't use a dimension for the color channel of grayscale

Color1{T} = Colorant{T,1}
Color2{T} = Colorant{T,2}
Color3{T} = Colorant{T,3}
Color4{T} = Colorant{T,4}
AColor{N,C,T} = AlphaColor{C,T,N}
ColorA{N,C,T} = ColorAlpha{C,T,N}
const NonparametricColors = Union{RGB24,ARGB32,Gray24,AGray32}

## ChannelView

struct ChannelView{T,N,A<:AbstractArray} <: AbstractArray{T,N}
    parent::A

    function ChannelView{T,N,A}(parent::AbstractArray{C}) where {T,N,A,C<:Colorant}
        n = length(channelview_indices(parent))
        n == N || throw(DimensionMismatch("for an $N-dimensional ChannelView with color type $C, input dimensionality should be $n instead of $(ndims(parent))"))
        new{T,N,A}(parent)
    end
end


"""
    ChannelView(A)

creates a "view" of the Colorant array `A`, splitting out (if
necessary) the separate color channels of `eltype(A)` into a new first
dimension. For example, if `A` is a m-by-n RGB{N0f8} array,
`ChannelView(A)` will return a 3-by-m-by-n N0f8 array. Color spaces with
a single element (i.e., grayscale) do not add a new first dimension of
`A`.

Of relevance for types like RGB and BGR, the channels of the returned
array will be in constructor-argument order, not memory order (see
`reinterpret` if you want to use memory order).

The opposite transformation is implemented by [`ColorView`](@ref). See
also [`channelview`](@ref).
"""
ChannelView(parent::AbstractArray) = _channelview(parent, channelview_indices(parent))
function _channelview(parent::AbstractArray{C}, inds::Indices{N}) where {C<:Colorant,N}
    # Creating a ChannelView in a type-stable fashion requires use of tuples to compute N+1
    ChannelView{eltype(C),N,typeof(parent)}(parent)
end

Color1Array{C<:Color1,N} = AbstractArray{C,N}
ChannelView1{T,N,A<:Color1Array} = ChannelView{T,N,A}

Base.parent(A::ChannelView) = A.parent
parenttype(::Type{ChannelView{T,N,A}}) where {T,N,A} = A
@inline Base.size(A::ChannelView)    = channelview_size(parent(A))
@inline Base.indices(A::ChannelView) = channelview_indices(parent(A))

# Can be IndexLinear for grayscale (1-channel images), otherwise must be IndexCartesian
Base.IndexStyle(::Type{T}) where {T<:ChannelView1} = IndexStyle(parenttype(T))

# colortype(A::ChannelView) = eltype(parent(A))

Base.@propagate_inbounds function Base.getindex(A::ChannelView{T,N}, I::Vararg{Int,N}) where {T,N}
    @boundscheck checkbounds(A, I...)
    P = parent(A)
    Ic, Ia = indexsplit(P, I)
    @inbounds ret = tuplify(P[Ia...])[Ic]
    ret
end

Base.@propagate_inbounds function Base.getindex(A::ChannelView1{T,1}, i::Int) where T # ambiguity
    @boundscheck checkbounds(A, i)
    @inbounds ret = eltype(A)(parent(A)[i])
    ret
end
Base.@propagate_inbounds function Base.getindex(A::ChannelView1, i::Int)
    @boundscheck checkbounds(A, i)
    @inbounds ret = eltype(A)(parent(A)[i])
    ret
end

Base.@propagate_inbounds function Base.setindex!(A::ChannelView{T,N}, val, I::Vararg{Int,N}) where {T,N}
    @boundscheck checkbounds(A, I...)
    P = parent(A)
    Ic, Ia = indexsplit(P, I)
    @inbounds c = P[Ia...]
    @inbounds P[Ia...] = setchannel(c, val, Ic)
    val
end

Base.@propagate_inbounds function Base.setindex!(A::ChannelView1{T,1}, val, i::Int) where T # amb
    @boundscheck checkbounds(A, i)
    @inbounds parent(A)[i] = val
    val
end
Base.@propagate_inbounds function Base.setindex!(A::ChannelView1, val, i::Int)
    @boundscheck checkbounds(A, i)
    @inbounds parent(A)[i] = val
    val
end

function Base.similar(A::ChannelView, ::Type{S}, dims::NTuple{N,Int}) where {S,N}
    P = parent(A)
    check_ncolorchan(P, dims)
    ChannelView(similar(P, base_colorant_type(eltype(P)){S}, chanparentsize(P, dims)))
end

## ColorView

"""
    ColorView{C}(A)

creates a "view" of the numeric array `A`, interpreting the first
dimension of `A` as if were the channels of a Colorant `C`. The first
dimension must have the proper number of elements for the constructor
of `C`. For example, if `A` is a 3-by-m-by-n N0f8 array,
`ColorView{RGB}(A)` will create an m-by-n array with element type
`RGB{N0f8}`. Color spaces with a single element (i.e., grayscale) do not
"consume" the first dimension of `A`.

Of relevance for types like RGB and BGR, the elements of `A`
are interpreted in constructor-argument order, not memory order (see
`reinterpret` if you want to use memory order).

The opposite transformation is implemented by
[`ChannelView`](@ref). See also [`colorview`](@ref).
"""
struct ColorView{C<:Colorant,N,A<:AbstractArray} <: AbstractArray{C,N}
    parent::A

    function ColorView{C,N,A}(parent::AbstractArray{T}) where {C,N,A,T<:Number}
        n = length(colorview_size(C, parent))
        n == N || throw(DimensionMismatch("for an $N-dimensional ColorView with color type $C, input dimensionality should be $n instead of $(ndims(parent))"))
        checkdim1(C, indices(parent))
        new{C,N,A}(parent)
    end
end

function ColorView{C}(parent::AbstractArray{T}) where {C<:Colorant,T<:Number}
    CT = ccolor_number(C, T)
    _ColorView(CT, eltype(CT), parent)
end
function _ColorView(::Type{C}, ::Type{T}, parent::AbstractArray{T}) where {C<:Colorant,T<:Number}
    # Creating a ColorView in a type-stable fashion requires use of tuples to compute N+1
    _colorview(C, parent, colorview_size(C, parent))
end
function _colorview(::Type{C}, parent::AbstractArray, sz::NTuple{N,Int}) where {C,N}
    ColorView{C,N,typeof(parent)}(parent)
end

ColorView(::AbstractArray) = error("specify the desired colorspace with ColorView{C}(parent)")

Base.parent(A::ColorView) = A.parent
@inline Base.size(A::ColorView) = colorview_size(eltype(A), parent(A))
@inline Base.indices(A::ColorView) = colorview_indices(eltype(A), parent(A))

Base.IndexStyle(::Type{ColorView{C,N,A}}) where {C<:Color1,N,A<:AbstractArray} = IndexStyle(A)
Base.IndexStyle(::Type{V}) where {V<:ColorView} = IndexCartesian()

Base.@propagate_inbounds function Base.getindex(A::ColorView{C,N}, I::Vararg{Int,N}) where {C,N}
    P = parent(A)
    @boundscheck Base.checkbounds_indices(Bool, parentindices(C, indices(P)), I) || Base.throw_boundserror(A, I)
    @inbounds ret = C(getchannels(P, C, I)...)
    ret
end

Base.@propagate_inbounds function Base.setindex!(A::ColorView{C,N}, val::C, I::Vararg{Int,N}) where {C,N}
    P = parent(A)
    @boundscheck Base.checkbounds_indices(Bool, parentindices(C, indices(P)), I) || Base.throw_boundserror(A, I)
    setchannels!(P, val, I)
    val
end
Base.@propagate_inbounds function Base.setindex!(A::ColorView{C,N}, val, I::Vararg{Int,N}) where {C,N}
    setindex!(A, convert(C, val), I...)
end

# A grayscale ColorView can be LinearFast, so support this too
Base.@propagate_inbounds function Base.getindex(A::ColorView{C,N}, i::Int) where {C<:Color1,N}
    P = parent(A)
    @boundscheck checkindex(Bool, linearindices(P), i) || Base.throw_boundserror(A, i)
    @inbounds ret = C(getchannels(P, C, i)[1])
    ret
end
Base.@propagate_inbounds function Base.setindex!(A::ColorView{C,1}, val::C, i::Int) where C<:Color1  # for ambiguity resolution
    P = parent(A)
    @boundscheck checkindex(Bool, linearindices(P), i) || Base.throw_boundserror(A, i)
    setchannels!(P, val, i)
    val
end
Base.@propagate_inbounds function Base.setindex!(A::ColorView{C,N}, val::C, i::Int) where {C<:Color1,N}
    P = parent(A)
    @boundscheck checkindex(Bool, linearindices(P), i) || Base.throw_boundserror(A, i)
    setchannels!(P, val, i)
    val
end
Base.@propagate_inbounds function Base.setindex!(A::ColorView{C,N}, val, i::Int) where {C<:Color1,N}
    setindex!(A, convert(C, val), i)
end

function Base.similar(A::ColorView, ::Type{S}, dims::NTuple{N,Int}) where {S<:Colorant,N}
    P = parent(A)
    ColorView{S}(similar(P, celtype(eltype(S), eltype(P)), colparentsize(S, dims)))
end
function Base.similar(A::ColorView, ::Type{S}, dims::NTuple{N,Int}) where {S<:Number,N}
    P = parent(A)
    similar(P, S, dims)
end
function Base.similar(A::ColorView, ::Type{S}, dims::NTuple{N,Int}) where {S<:NonparametricColors,N}
    P = parent(A)
    similar(P, S, dims)
end

## Construct a view that's conceptually equivalent to a ChannelView or ColorView,
## but which may be simpler (i.e., strip off a wrapper or use reinterpret)

"""
    channelview(A)

returns a view of `A`, splitting out (if necessary) the color channels
of `A` into a new first dimension. This is almost identical to
`ChannelView(A)`, except that if `A` is a `ColorView`, it will simply
return the parent of `A`, or will use `reinterpret` when appropriate.
Consequently, the output may not be a [`ChannelView`](@ref) array.

Of relevance for types like RGB and BGR, the channels of the returned
array will be in constructor-argument order, not memory order (see
`reinterpret` if you want to use memory order).
"""
channelview(A::AbstractArray{T}) where {T<:Number} = A
channelview(A::AbstractArray) = ChannelView(A)
channelview(A::ColorView) = parent(A)
channelview(A::Array{RGB{T}}) where {T} = reinterpret(T, A)
channelview(A::Array{C}) where {C<:AbstractRGB} = ChannelView(A) # BGR, RGB1, etc don't satisfy conditions
channelview(A::Array{C}) where {C<:Color} = reinterpret(eltype(C), A)
channelview(A::Array{C}) where {C<:ColorAlpha} = _channelview(base_color_type(C), A)
_channelview(::Type{RGB}, A) = reinterpret(eltype(eltype(A)), A)
_channelview(::Type{C}, A) where {C<:AbstractRGB} = ChannelView(A)
_channelview(::Type{C}, A) where {C<:Color} = reinterpret(eltype(eltype(A)), A)


"""
    colorview(C, A)

returns a view of the numeric array `A`, interpreting successive
elements of `A` as if they were channels of Colorant `C`. This is
almost identical to `ColorView{C}(A)`, except that if `A` is a
`ChannelView`, it will simply return the parent of `A`, or use
`reinterpret` when appropriate. Consequently, the output may not be a
[`ColorView`](@ref) array.

Of relevance for types like RGB and BGR, the elements of `A` are
interpreted in constructor-argument order, not memory order (see
`reinterpret` if you want to use memory order).

# Example
```jl
A = rand(3, 10, 10)
img = colorview(RGB, A)
```
"""
colorview(::Type{C}, A::AbstractArray{T}) where {C<:Colorant,T<:Number} =
    _ccolorview(ccolor_number(C, T), A)
_ccolorview(::Type{C}, A::AbstractArray{T}) where {T<:Number,C<:Colorant} = ColorView{C}(A)
_ccolorview(::Type{C}, A::Array{T}) where {T<:Number,C<:RGB{T}} = reinterpret(C, A)
_ccolorview(::Type{C}, A::Array{T}) where {T<:Number,C<:AbstractRGB} = ColorView{C}(A)
_ccolorview(::Type{C}, A::Array{T}) where {T<:Number,C<:Color{T}} = reinterpret(C, A)
_ccolorview(::Type{C}, A::Array{T}) where {T<:Number,C<:ColorAlpha} =
    _colorviewalpha(base_color_type(C), C, eltype(C), A)
_colorviewalpha(::Type{C}, ::Type{CA}, ::Type{T}, A::Array{T}) where {C<:RGB,CA,T} =
    reinterpret(CA, A)
_colorviewalpha(::Type{C}, ::Type{CA}, ::Type, A::Array) where {C<:AbstractRGB,CA} =
    ColorView{CA}(A)
_colorviewalpha(::Type{C}, ::Type{CA}, ::Type{T}, A::Array{T}) where {C<:Color,CA,T} =
    reinterpret(CA, A)

colorview(::Type{C1}, A::AbstractArray{C2}) where {C1<:Colorant,C2<:Colorant} =
    colorview(C1, channelview(A))

function colorview(::Type{C}, A::ChannelView) where C<:Colorant
    P = parent(A)
    C0 = ccolor_number(C, eltype(A))
    _colorview_chanview(C0, base_colorant_type(C), base_colorant_type(eltype(P)), P, A)
end
_colorview_chanview(::Type{C0}, ::Type{C}, ::Type{C}, P, A::AbstractArray{T}) where {T<:Number,C0<:Colorant{T},C<:Colorant} = P
_colorview_chanview(::Type{C0}, ::Type, ::Type, P, A) where {C0} =
    _ccolorview(ccolor_number(C0, eltype(A)), A)

"""
    colorview(C, gray1, gray2, ...) -> imgC

Combine numeric/grayscale images `gray1`, `gray2`, etc., into the
separate color channels of an array `imgC` with element type
`C<:Colorant`.

As a convenience, the constant `zeroarray` fills in an array of
matched size with all zeros.

# Example
```julia
imgC = colorview(RGB, r, zeroarray, b)
```

creates an image with `r` in the red chanel, `b` in the blue channel,
and nothing in the green channel.

See also: [`StackedView`](@ref).
"""
function colorview(::Type{C}, gray1, gray2, grays...) where C<:Colorant
    T = _colorview_type(eltype(C), promote_eleltype_all(gray1, gray2, grays...))
    sv = StackedView{T}(gray1, gray2, grays...)
    CT = base_colorant_type(C){T}
    colorview(CT, sv)
end

_colorview_type(::Type{Any}, ::Type{T}) where {T} = T
_colorview_type(::Type{T1}, ::Type{T2}) where {T1,T2} = T1

Base.@pure promote_eleltype_all(gray, grays...) = _promote_eleltype_all(beltype(eltype(gray)), grays...)
@inline function _promote_eleltype_all(::Type{T}, gray, grays...) where T
    _promote_eleltype_all(promote_type(T, beltype(eltype(gray))), grays...)
end
_promote_eleltype_all(::Type{T}) where {T} = T

beltype(::Type{T}) where {T} = eltype(T)
beltype(::Type{Union{}}) = Union{}

## Tuple & indexing utilities

_size(A::AbstractArray) = map(length, indices(A))

# color->number
@inline channelview_size(parent::AbstractArray{C}) where {C<:Colorant} = (length(C), _size(parent)...)
@inline channelview_indices(parent::AbstractArray{C}) where {C<:Colorant} =
    _cvi(Base.OneTo(length(C)), indices(parent))
_cvi(rc, ::Tuple{}) = (rc,)
_cvi(rc, inds::Tuple{R,Vararg{R}}) where {R<:AbstractUnitRange} = (convert(R, rc), inds...)
if squeeze1
    @inline channelview_size(parent::AbstractArray{C}) where {C<:Color1} = _size(parent)
    @inline channelview_indices(parent::AbstractArray{C}) where {C<:Color1} = indices(parent)
end

function check_ncolorchan(::AbstractArray{C}, dims) where C<:Colorant
    dims[1] == length(C) || throw(DimensionMismatch("new array has $(dims[1]) color channels, must have $(length(C))"))
end
chanparentsize(::AbstractArray{C}, dims) where {C<:Colorant} = tail(dims)
@inline colparentsize(::Type{C}, dims) where {C<:Colorant} = (length(C), dims...)

channelview_dims_offset(parent::AbstractArray{C}) where {C<:Colorant} = 1

if squeeze1
    check_ncolorchan(::AbstractArray{C}, dims) where {C<:Color1} = nothing
    chanparentsize(::AbstractArray{C}, dims) where {C<:Color1} = dims
    colparentsize(::Type{C}, dims) where {C<:Color1} = dims
    channelview_dims_offset(parent::AbstractArray{C}) where {C<:Color1} = 0
end

@inline indexsplit(A::AbstractArray{C}, I) where {C<:Colorant} = I[1], tail(I)

if squeeze1
    @inline indexsplit(A::AbstractArray{C}, I) where {C<:Color1} = 1, I
end

# number->color
@inline colorview_size(::Type{C}, parent::AbstractArray) where {C<:Colorant} = tail(_size(parent))
@inline colorview_indices(::Type{C}, parent::AbstractArray) where {C<:Colorant} = tail(indices(parent))
if squeeze1
    @inline colorview_size(::Type{C}, parent::AbstractArray) where {C<:Color1} = _size(parent)
    @inline colorview_indices(::Type{C}, parent::AbstractArray) where {C<:Color1} = indices(parent)
end

function checkdim1(::Type{C}, inds) where C<:Colorant
    inds[1] == (1:length(C)) || throw(DimensionMismatch("dimension 1 must have indices 1:$(length(C)), got $(inds[1])"))
    nothing
end
if squeeze1
    checkdim1(::Type{C}, dims) where {C<:Color1} = nothing
end

parentindices(::Type, inds) = tail(inds)
if squeeze1
    parentindices(::Type{C}, inds) where {C<:Color1} = inds
end

celtype(::Type{Any}, ::Type{T}) where {T} = T
celtype(::Type{T1}, ::Type{T2}) where {T1,T2} = T1

## Low-level color utilities

tuplify(c::Color1) = (comp1(c),)
tuplify(c::Color3) = (comp1(c), comp2(c), comp3(c))
tuplify(c::Color2) = (comp1(c), alpha(c))
tuplify(c::Color4) = (comp1(c), comp2(c), comp3(c), alpha(c))

"""
    getchannels(P, C::Type, I)

Get a tuple of all channels needed to construct a Colorant of type `C`
from an `P::AbstractArray{<:Number}`.
"""
getchannels
if squeeze1
    @inline getchannels(P, ::Type{C}, I) where {C<:Color1} = (@inbounds ret = (P[I...],); ret)
    @inline getchannels(P, ::Type{C}, I::Real) where {C<:Color1} = (@inbounds ret = (P[I],); ret)
else
    @inline getchannels(P, ::Type{C}, I) where {C<:Color1} = (@inbounds ret = (P[1, I...],); ret)
    @inline getchannels(P, ::Type{C}, I::Real) where {C<:Color1} = (@inbounds ret = (P[1, I],); ret)
end
@inline function getchannels(P, ::Type{C}, I) where C<:Color2
    @inbounds ret = (P[1,I...], P[2,I...])
    ret
end
@inline function getchannels(P, ::Type{C}, I) where C<:Color3
    @inbounds ret = (P[1,I...], P[2,I...],P[3,I...])
    ret
end
@inline function getchannels(P, ::Type{C}, I) where C<:Color4
    @inbounds ret = (P[1,I...], P[2,I...], P[3,I...], P[4,I...])
    ret
end

# setchannel (similar to setfield!)
# These don't check bounds since that's already done
"""
    setchannel(c, val, idx)

Equivalent to:

    cc = copy(c)
    cc[idx] = val
    cc

for immutable colors. `idx` is interpreted in the sense of constructor
arguments, so `setchannel(c, 0.5, 1)` would set red color channel for
any `c::AbstractRGB`, even if red isn't the first field in the type.
"""
setchannel(c::Colorant{T,1}, val, Ic::Int) where {T} = typeof(c)(val)

setchannel(c::TransparentColor{C,T,2}, val, Ic::Int) where {C,T} =
    typeof(c)(ifelse(Ic==1,val,comp1(c)),
              ifelse(Ic==2,val,alpha(c)))

setchannel(c::Colorant{T,3}, val, Ic::Int) where {T} = typeof(c)(ifelse(Ic==1,val,comp1(c)),
                                                          ifelse(Ic==2,val,comp2(c)),
                                                          ifelse(Ic==3,val,comp3(c)))
setchannel(c::TransparentColor{C,T,4}, val, Ic::Int) where {C,T} =
    typeof(c)(ifelse(Ic==1,val,comp1(c)),
              ifelse(Ic==2,val,comp2(c)),
              ifelse(Ic==3,val,comp3(c)),
              ifelse(Ic==4,val,alpha(c)))

"""
    setchannels!(P, val, I)

For a color `val`, distribute its channels along `P[:, I...]` for
`P::AbstractArray{<:Number}`.
"""
setchannels!
if squeeze1
    @inline setchannels!(P, val::Color1, I) = (@inbounds P[I...] = comp1(val); val)
else
    @inline setchannels!(P, val::Color1, I) = (@inbounds P[1,I...] = comp1(val); val)
end
@inline function setchannels!(P, val::Color2, I)
    @inbounds P[1,I...] = comp1(val)
    @inbounds P[2,I...] = alpha(val)
    val
end
@inline function setchannels!(P, val::Color3, I)
    @inbounds P[1,I...] = comp1(val)
    @inbounds P[2,I...] = comp2(val)
    @inbounds P[3,I...] = comp3(val)
    val
end
@inline function setchannels!(P, val::Color4, I)
    @inbounds P[1,I...] = comp1(val)
    @inbounds P[2,I...] = comp2(val)
    @inbounds P[3,I...] = comp3(val)
    @inbounds P[4,I...] = alpha(val)
    val
end
