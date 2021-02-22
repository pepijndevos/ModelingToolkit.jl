"""
```julia
calculate_tgrad(sys::AbstractSystem)
```

Calculate the time gradient of a system.

Returns a vector of [`Num`](@ref) instances. The result from the first
call will be cached in the system object.
"""
function calculate_tgrad end

"""
```julia
calculate_gradient(sys::AbstractSystem)
```

Calculate the gradient of a scalar system.

Returns a vector of [`Num`](@ref) instances. The result from the first
call will be cached in the system object.
"""
function calculate_gradient end

"""
```julia
calculate_jacobian(sys::AbstractSystem)
```

Calculate the jacobian matrix of a system.

Returns a matrix of [`Num`](@ref) instances. The result from the first
call will be cached in the system object.
"""
function calculate_jacobian end

"""
```julia
calculate_factorized_W(sys::AbstractSystem)
```

Calculate the factorized W-matrix of a system.

Returns a matrix of [`Num`](@ref) instances. The result from the first
call will be cached in the system object.
"""
function calculate_factorized_W end

"""
```julia
calculate_hessian(sys::AbstractSystem)
```

Calculate the hessian matrix of a scalar system.

Returns a matrix of [`Num`](@ref) instances. The result from the first
call will be cached in the system object.
"""
function calculate_hessian end

"""
```julia
generate_tgrad(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; kwargs...)
```

Generates a function for the time gradient of a system. Extra arguments control
the arguments to the internal [`build_function`](@ref) call.
"""
function generate_tgrad end

"""
```julia
generate_gradient(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; kwargs...)
```

Generates a function for the gradient of a system. Extra arguments control
the arguments to the internal [`build_function`](@ref) call.
"""
function generate_gradient end

"""
```julia
generate_jacobian(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; sparse = false, kwargs...)
```

Generates a function for the jacobian matrix matrix of a system. Extra arguments control
the arguments to the internal [`build_function`](@ref) call.
"""
function generate_jacobian end

"""
```julia
generate_factorized_W(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; sparse = false, kwargs...)
```

Generates a function for the factorized W-matrix matrix of a system. Extra arguments control
the arguments to the internal [`build_function`](@ref) call.
"""
function generate_factorized_W end

"""
```julia
generate_hessian(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; sparse = false, kwargs...)
```

Generates a function for the hessian matrix matrix of a system. Extra arguments control
the arguments to the internal [`build_function`](@ref) call.
"""
function generate_hessian end

"""
```julia
generate_function(sys::AbstractSystem, dvs = states(sys), ps = parameters(sys), expression = Val{true}; kwargs...)
```

Generate a function to evaluate the system's equations.
"""
function generate_function end

Base.nameof(sys::AbstractSystem) = getfield(sys, :name)

function getname(t)
    if istree(t)
        operation(t) isa Sym ? getname(operation(t)) : error("Cannot get name of $t")
    else
        nameof(t)
    end
end

independent_variable(sys::AbstractSystem) = isdefined(sys, :iv) ? getfield(sys, :iv) : nothing

function structure(sys::AbstractSystem)
    s = get_structure(sys)
    s isa SystemStructure || throw(ArgumentError("SystemStructure is not yet initialized, please run `sys = initialize_system_structure(sys)` or `sys = alias_elimination(sys)`."))
    return s
end
for prop in [
             :eqs
             :noiseeqs
             :iv
             :states
             :ps
             :default_p
             :default_u0
             :observed
             :tgrad
             :jac
             :Wfact
             :Wfact_t
             :systems
             :structure
             :op
             :equality_constraints
             :inequality_constraints
             :controls
             :loss
            ]
    fname1 = Symbol(:get_, prop)
    fname2 = Symbol(:has_, prop)
    @eval begin
        $fname1(sys::AbstractSystem) = getfield(sys, $(QuoteNode(prop)))
        $fname2(sys::AbstractSystem) = isdefined(sys, $(QuoteNode(prop)))
    end
end

Setfield.get(obj::AbstractSystem, l::Setfield.PropertyLens{field}) where {field} = getfield(obj, field)
@generated function ConstructionBase.setproperties(obj::AbstractSystem, patch::NamedTuple)
    if issubset(fieldnames(patch), fieldnames(obj))
        args = map(fieldnames(obj)) do fn
            if fn in fieldnames(patch)
                :(patch.$fn)
            else
                :(getfield(obj, $(Meta.quot(fn))))
            end
        end
        return Expr(:block,
            Expr(:meta, :inline),
            Expr(:call,:(constructorof($obj)), args...)
        )
    else
        error("This should never happen. Trying to set $(typeof(obj)) with $patch.")
    end
end

function Base.getproperty(sys::AbstractSystem, name::Symbol)
    sysname = nameof(sys)
    systems = get_systems(sys)
    if isdefined(sys, name)
        Base.depwarn("`sys.name` like `sys.$name` is deprecated. Use getters like `get_$name` instead.", "sys.$name")
        return getfield(sys, name)
    elseif !isempty(systems)
        i = findfirst(x->nameof(x)==name,systems)
        if i !== nothing
            return rename(systems[i],renamespace(sysname,name))
        end
    end

    sts = get_states(sys)
    i = findfirst(x->getname(x) == name, sts)

    if i !== nothing
        return rename(sts[i],renamespace(sysname,name))
    end

    if has_ps(sys)
        ps = get_ps(sys)
        i = findfirst(x->getname(x) == name,ps)
        if i !== nothing
            return rename(ps[i],renamespace(sysname,name))
        end
    end

    if has_observed(sys)
        obs = get_observed(sys)
        i = findfirst(x->getname(x.lhs)==name,obs)
        if i !== nothing
            return rename(obs[i].lhs,renamespace(sysname,name))
        end
    end

    throw(error("Variable $name does not exist"))
end

function Base.setproperty!(sys::AbstractSystem, prop::Symbol, val)
    if (pa = Sym{Parameter{Real}}(prop); pa in parameters(sys))
        sys.default_p[pa] = value(val)
    # comparing a Sym returns a symbolic expression
    elseif (st = Sym{Real}(prop); any(s->s.name==st.name, states(sys)))
        sys.default_u0[st] = value(val)
    else
        setfield!(sys, prop, val)
    end
end

function renamespace(namespace, x)
    if x isa Num
        renamespace(namespace, value(x))
    elseif istree(x)
        renamespace(namespace, operation(x))(arguments(x)...)
    elseif x isa Sym
        Sym{symtype(x)}(renamespace(namespace,nameof(x)))
    else
        Symbol(namespace,:₊,x)
    end
end

namespace_variables(sys::AbstractSystem) = states(sys, states(sys))
namespace_parameters(sys::AbstractSystem) = parameters(sys, parameters(sys))

function namespace_default_u0(sys)
    d_u0 = default_u0(sys)
    Dict(states(sys, k) => namespace_expr(d_u0[k], nameof(sys), independent_variable(sys)) for k in keys(d_u0))
end

function namespace_default_p(sys)
    d_p = default_p(sys)
    Dict(parameters(sys, k) => namespace_expr(d_p[k], nameof(sys), independent_variable(sys)) for k in keys(d_p))
end

function namespace_equations(sys::AbstractSystem)
    eqs = equations(sys)
    isempty(eqs) && return Equation[]
    iv = independent_variable(sys)
    map(eq->namespace_equation(eq,nameof(sys),iv), eqs)
end

function namespace_equation(eq::Equation,name,iv)
    _lhs = namespace_expr(eq.lhs,name,iv)
    _rhs = namespace_expr(eq.rhs,name,iv)
    _lhs ~ _rhs
end

function namespace_expr(O::Sym,name,iv)
    isequal(O, iv) ? O : rename(O,renamespace(name,nameof(O)))
end

_symparam(s::Symbolic{T}) where {T} = T
function namespace_expr(O,name,iv) where {T}
    if istree(O)
        renamed = map(a->namespace_expr(a,name,iv), arguments(O))
        if operation(O) isa Sym
            renamed_op = rename(operation(O),renamespace(name,nameof(operation(O))))
            Term{_symparam(O)}(renamed_op,renamed)
        else
            similarterm(O,operation(O),renamed)
        end
    else
        O
    end
end

function states(sys::AbstractSystem)
    sts = get_states(sys)
    systems = get_systems(sys)
    unique(isempty(systems) ?
           sts :
           [sts;reduce(vcat,namespace_variables.(systems))])
end
function parameters(sys::AbstractSystem)
    ps = get_ps(sys)
    systems = get_systems(sys)
    isempty(systems) ? ps : [ps;reduce(vcat,namespace_parameters.(systems))]
end
function observed(sys::AbstractSystem)
    iv = independent_variable(sys)
    obs = get_observed(sys)
    systems = get_systems(sys)
    [obs;
     reduce(vcat,
            (map(o->namespace_equation(o, nameof(s), iv), observed(s)) for s in systems),
            init=Equation[])]
end

function default_u0(sys::AbstractSystem)
    systems = get_systems(sys)
    d_u0 = get_default_u0(sys)
    isempty(systems) ? d_u0 : mapreduce(namespace_default_u0, merge, systems; init=d_u0)
end

function default_p(sys::AbstractSystem)
    systems = get_systems(sys)
    d_p = get_default_p(sys)
    isempty(systems) ? d_p : mapreduce(namespace_default_p, merge, systems; init=d_p)
end

states(sys::AbstractSystem, v) = renamespace(nameof(sys), v)
parameters(sys::AbstractSystem, v) = toparam(states(sys, v))
for f in [:states, :parameters]
    @eval $f(sys::AbstractSystem, vs::AbstractArray) = map(v->$f(sys, v), vs)
end

lhss(xs) = map(x->x.lhs, xs)
rhss(xs) = map(x->x.rhs, xs)

flatten(sys::AbstractSystem) = sys

function equations(sys::ModelingToolkit.AbstractSystem)
    eqs = get_eqs(sys)
    systems = get_systems(sys)
    if isempty(systems)
        return eqs
    else
        eqs = Equation[eqs;
               reduce(vcat,
                      namespace_equations.(get_systems(sys));
                      init=Equation[])]
        return eqs
    end
end

function islinear(sys::AbstractSystem)
    rhs = [eq.rhs for eq ∈ equations(sys)]

    all(islinear(r, states(sys)) for r in rhs)
end

struct AbstractSysToExpr
    sys::AbstractSystem
    states::Vector
end
AbstractSysToExpr(sys) = AbstractSysToExpr(sys,states(sys))
function (f::AbstractSysToExpr)(O)
    !istree(O) && return toexpr(O)
    any(isequal(O), f.states) && return nameof(operation(O))  # variables
    if isa(operation(O), Sym)
        return build_expr(:call, Any[nameof(operation(O)); f.(arguments(O))])
    end
    return build_expr(:call, Any[operation(O); f.(arguments(O))])
end

function Base.show(io::IO, sys::AbstractSystem)
    eqs = equations(sys)
    Base.printstyled(io, "Model $(nameof(sys)) with $(length(eqs)) equations\n"; bold=true)
    # The reduced equations are usually very long. It's not that useful to print
    # them.
    #Base.print_matrix(io, eqs)
    #println(io)

    rows = first(displaysize(io)) ÷ 5
    limit = get(io, :limit, false)

    vars = states(sys); nvars = length(vars)
    Base.printstyled(io, "States ($nvars):"; bold=true)
    nrows = min(nvars, limit ? rows : nvars)
    limited = nrows < length(vars)
    d_u0 = has_default_u0(sys) ? default_u0(sys) : nothing
    for i in 1:nrows
        s = vars[i]
        print(io, "\n  ", s)

        if d_u0 !== nothing
            val = get(d_u0, s, nothing)
            if val !== nothing
                print(io, " [defaults to $val]")
            end
        end
    end
    limited && print(io, "\n⋮")
    println(io)

    vars = parameters(sys); nvars = length(vars)
    Base.printstyled(io, "Parameters ($nvars):"; bold=true)
    nrows = min(nvars, limit ? rows : nvars)
    limited = nrows < length(vars)
    d_p = has_default_p(sys) ? default_p(sys) : nothing
    for i in 1:nrows
        s = vars[i]
        print(io, "\n  ", s)

        if d_p !== nothing
            val = get(d_p, s, nothing)
            if val !== nothing
                print(io, " [defaults to $val]")
            end
        end
    end
    limited && print(io, "\n⋮")

    if has_structure(sys)
        s = get_structure(sys)
        if s !== nothing
            Base.printstyled(io, "\nIncidence matrix:"; color=:magenta)
            show(io, incidence_matrix(s.graph, Num(Sym{Real}(:×))))
        end
    end
    return nothing
end
