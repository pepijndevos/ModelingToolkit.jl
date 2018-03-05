struct DiffEqSystem <: AbstractSystem
    eqs::Vector{Operation}
    ivs::Vector{Variable}
    dvs::Vector{Variable}
    vs::Vector{Variable}
    ps::Vector{Variable}
end
function DiffEqSystem(eqs)
    ivs, dvs, vs, ps = extract_elements(eqs, (:IndependentVariable, :DependentVariable, :Variable, :Parameter))
    DiffEqSystem(eqs, ivs, dvs, vs, ps)
end
function DiffEqSystem(eqs, ivs)
    dvs, vs, ps = extract_elements(eqs, (:DependentVariable, :Variable, :Parameter))
    DiffEqSystem(eqs, ivs, dvs, vs, ps)
end

function generate_ode_function(sys::DiffEqSystem)
    var_exprs = [:($(sys.dvs[i].name) = u[$i]) for i in 1:length(sys.dvs)]
    param_exprs = [:($(sys.ps[i].name) = p[$i]) for i in 1:length(sys.ps)]
    sys_exprs = build_equals_expr.(sys.eqs)
    dvar_exprs = [:(du[$i] = $(Symbol("$(sys.dvs[i].name)_$(sys.ivs[1].name)"))) for i in 1:length(sys.dvs)]
    exprs = vcat(var_exprs,param_exprs,sys_exprs,dvar_exprs)
    block = expr_arr_to_block(exprs)
    :((du,u,p,t)->$(block))
end

function build_equals_expr(eq)
    @assert typeof(eq.args[1]) <: Variable
    if eq.args[1].diff != nothing
        # Differential statement
        :($(Symbol("$(eq.args[1].name)_$(eq.args[1].diff.x.name)")) = $(eq.args[2]))
    else
        # Intermediate calculation
        :($(Symbol("$(eq.args[1].name)")) = $(eq.args[2]))
    end
end

function generate_ode_jacobian(sys::DiffEqSystem,simplify=true)
    var_exprs = [:($(sys.dvs[i].name) = u[$i]) for i in 1:length(sys.dvs)]
    param_exprs = [:($(sys.ps[i].name) = p[$i]) for i in 1:length(sys.ps)]
    diff_idxs = map(eq->eq.args[1].diff !=nothing,sys.eqs)
    diff_exprs = sys.eqs[diff_idxs]
    rhs = [eq.args[2] for eq in diff_exprs]
    calcs = sys.eqs[.!(diff_idxs)]
    for i in 1:length(calcs)
        find_replace!.(rhs,calcs[i].args[1],calcs[i].args[2])
    end
    sys_exprs = calculate_jacobian(rhs,sys.dvs)
    sys_exprs = Expression[expand_derivatives(expr) for expr in sys_exprs]
    if simplify
        sys_exprs = Expression[simplify_constants(expr) for expr in sys_exprs]
    end
    sys_exprs
end

function DiffEqBase.DiffEqFunction(sys::DiffEqSystem)
    expr = generate_ode_function(sys)
    DiffEqFunction{true}(eval(expr))
end

struct NonlinearSystem <: AbstractSystem
    eqs::Vector{Operation}
    vs::Vector{Variable}
    ps::Vector{Variable}
end

function NonlinearSystem(eqs)
    # Allow the use of :DependentVariable to make it seamless with DE use
    dvs, vs, ps = extract_elements(eqs, (:DependentVariable, :Variable, :Parameter))
    vs = [dvs;vs]
    NonlinearSystem(eqs, vs, ps)
end

function generate_nlsys_function(sys::NonlinearSystem)
    var_exprs = [:($(sys.vs[i].name) = u[$i]) for i in 1:length(sys.vs)]
    param_exprs = [:($(sys.ps[i].name) = p[$i]) for i in 1:length(sys.ps)]
    sys_idxs = map(eq->isequal(eq.args[1],Constant(0)),sys.eqs)
    sys_eqs = sys.eqs[sys_idxs]
    calc_eqs = sys.eqs[.!(sys_idxs)]
    calc_exprs = [:($(Symbol("$(eq.args[1].name)")) = $(eq.args[2])) for eq in calc_eqs]
    sys_exprs = [:($(Symbol("resid[$i]")) = $(sys_eqs[i].args[2])) for i in eachindex(sys_eqs)]

    exprs = vcat(var_exprs,param_exprs,calc_exprs,sys_exprs)
    block = expr_arr_to_block(exprs)
    :((du,u,p)->$(block))
end

function generate_nlsys_jacobian(sys::NonlinearSystem,simplify=true)
    var_exprs = [:($(sys.vs[i].name) = u[$i]) for i in 1:length(sys.vs)]
    param_exprs = [:($(sys.ps[i].name) = p[$i]) for i in 1:length(sys.ps)]

    sys_idxs = map(eq->isequal(eq.args[1],Constant(0)),sys.eqs)
    sys_eqs = sys.eqs[sys_idxs]
    calc_eqs = sys.eqs[.!(sys_idxs)]
    sys_exprs = [:($(Symbol("resid[$i]")) = $(sys_eqs[i].args[2])) for i in eachindex(sys_eqs)]
    rhs = [eq.args[2] for eq in sys_eqs]

    for i in 1:length(calc_eqs)
        find_replace!.(rhs,calc_eqs[i].args[1],calc_eqs[i].args[2])
    end

    sys_exprs = calculate_jacobian(rhs,sys.vs)
    sys_exprs = Expression[expand_derivatives(expr) for expr in sys_exprs]
    if simplify
        sys_exprs = Expression[simplify_constants(expr) for expr in sys_exprs]
    end
    sys_exprs
end

export DiffEqSystem, NonlinearSystem, DiffEqFunction
export generate_ode_function, generate_nlsys_function