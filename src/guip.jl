""" 
    r(t, x, T, v, P)

Returns ``r(t,x) = \\operatorname{grad}_x \\log p(t,x; T, v)`` where
``p`` is the transition density of the process ``P``.
""" 
function r(t, x, T, v, P)
    H(t, T, P, V(t, T, v, P) - x)
end

tau(s, t, T) = t + (s.-t).*(2-(s-t)/(T-t))
tau(ss::Vector) = tau(ss, ss[1], ss[end])

#####################


"""
    BridgeProp(Target::ContinuousTimeProcess, tt, v, a, cs)

Simple bridge proposal derived from a linear process with time dependent drift given by a [`CSpline`](@ref)
and constant diffusion coefficient `a`.

"""
struct BridgeProp{T} <: ContinuousTimeProcess{T}
    Target
    tt::Vector{Float64}
    v::Tuple{T,T}
    cs::CSpline{T}
    a
    Γ
    BridgeProp{T}(Target::ContinuousTimeProcess{T}, tt, v, a, cs) where T = 
        new(Target, tt, v, cs, a, inv(a))
end
BridgeProp(Target::ContinuousTimeProcess{T}, tt, v, a, cs=CSpline(first(tt), last(tt), zero(T))) where {T} = BridgeProp{T}(Target, tt, v, a, cs)

h(t,x, P::BridgeProp) = P.v[2] - x -  integrate(P.cs, t,  last(P.tt))
b(t, x, P::BridgeProp) = b(t, x, P.Target) + a(t, x, P.Target)*r(t, x, P) 
bi(i, x, P::BridgeProp) = b(P.tt[i], x, P.Target) + a(P.tt[i], x, P.Target)*r(P.tt[i], x, P) 

function bderiv(t, x, P::BridgeProp) 
    assert(constdiff(P))
    bderiv(t, x, P.Target) - a(t, x, P.Target)*P.Γ/(last(P.tt) - t)
end    

σ(t, x, P::BridgeProp) = σ(t, x, P.Target)
a(t, x, P::BridgeProp) = a(t, x, P.Target)
Γ(t, x, P::BridgeProp) = Γ(t, x, P.Target)
constdiff(P::BridgeProp) = constdiff(P.Target)

btilde(t, x, P::BridgeProp) = P.cs(t)
atilde(t, x, P::BridgeProp) = P.a
ptilde(P::BridgeProp) = Ptilde(P.cs, σ(last(P.tt), P.v[2], P.Target))

 
function r(t, x, P::BridgeProp) 
    P.Γ*h(t, x, P)/(last(P.tt) - t)
end
function H(t, x, P::BridgeProp) 
    P.Γ/(last(P.tt) - t)
end

function lptilde(P::BridgeProp{T}) where T 
    logpdfnormal(P.v[2] - (P.v[1] + integrate(P.cs, first(P.tt), last(P.tt))), (last(P.tt) - first(P.tt))*P.a)
end


"""
    GuidedProp

General bridge proposal process, only assuming that `Pt` defines `H` and `r` in the right way.
"""    
struct GuidedProp{T} <: ContinuousTimeProcess{T}
    Target
    t0; v0; t1; v1
    Pt::ContinuousTimeProcess{T}
    GuidedProp{T}(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1, Pt) where T = 
        new(Target, t0, v0, t1, v1, Pt)
end

GuidedProp(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1, Pt::ContinuousTimeProcess{T}) where {T} = GuidedProp{T}(Target, t0, v0, t1, v1, Pt)


V(t, P::GuidedProp) = V(t, P.t1, P.v1, P.Pt) 
dotV(t, P::GuidedProp) = dotV(t, P.t1, P.v1, P.Pt) 
r(t, x, P::GuidedProp) = r(t, x, P.t1, P.v1, P.Pt) 
b(t, x, P::GuidedProp) = b(t, x, P.Target) + a(t, x, P.Target)*r(t, x, P.t1, P.v1, P.Pt) 
σ(t, x, P::GuidedProp) = σ(t, x, P.Target)
a(t, x, P::GuidedProp) = a(t, x, P.Target)
Γ(t, x, P::GuidedProp) = Γ(t, x, P.Target)
constdiff(P::GuidedProp) = constdiff(P.Target) && constdiff(P.Pt)

btilde(t, x, P::GuidedProp) = b(t,x,P.Pt)
atilde(t, x, P::GuidedProp) = a(t,x,P.Pt)
ptilde(P::GuidedProp) = P.Pt

function lptilde(P::GuidedProp) 
     lp(P.t0, P.v0, P.t1, P.v1, P.Pt) 
end

#################################################
"""
    LinearNoiseAppr(tt, P, x, a, direction = forward) 

Precursor of the linear noise approximation of `P`. For now no attempt is taken 
to add in a linearization around the deterministic path. `direction` can be one of
`:forward`, `:backward` or `:nothing`. The latter corresponds to choosing `β == 0`.
"""
struct LinearNoiseAppr{R,S,T} <: ContinuousTimeProcess{T}
    Target::R
    Y::SamplePath{T}
    a::S
    function LinearNoiseAppr(tt_, P::R, x::T, a::S, direction = forward) where {R,S,T}
        tt = collect(tt_)
        N = length(tt)
        Y = SamplePath(tt, zeros(T, N)) 
        if direction == :forward
            solve!(R3(), b, Y, x, P) 
        elseif direction == :backward
            solvebackward!(R3(), b, Y, x, P)
        elseif direction != :nothing
            throw(ArgumentError("Wrong `direction`"))
        end
        new{R,S,T}(P, Y, a)
    end
end


bi(i, x, P::LinearNoiseAppr) = βi(max(i,2), P)
Bi(i, P::LinearNoiseAppr) = 0I
βi(i, P::LinearNoiseAppr) = (P.Y.yy[i]-P.Y.yy[i-1])/(P.Y.tt[i]-P.Y.tt[i-1])
ai(i, P::LinearNoiseAppr) = P.a
a(t, x, P::LinearNoiseAppr) = P.a
constdiff(::LinearNoiseAppr) = true
hasbi(::LinearNoiseAppr) = true


"""
    GuidedBridge

Guided proposal process for diffusion bridge using backward recursion.
    
    GuidedBridge(tt, P, Pt, v)

Constructor of guided proposal process for diffusion bridge of `P` to `v` on 
the time grid `tt` using guiding term derived from linear process `Pt`.

    GuidedPBridge(tt, P, Pt, V, H♢)

Guided proposal process for diffusion bridge of `P` to `v` on 
the time grid `tt` using guiding term derived from linear process `Pt`.
Initialize using [`Bridge.gpupdate`](@ref)(H♢, V, L, Σ, v)
"""   
struct GuidedBridge{T,S,R2,R} <: ContinuousTimeProcess{T}
    Target::R
    Pt::R2
    tt::Vector{Float64}
    H♢::Vector{S} 
    V::Vector{T}

    function GuidedBridge(tt_, P::R, Pt::R2, v::T, h♢::S = Bridge.outer(zero(v))) where {T,R,R2,S}
        tt = collect(tt_)
        N = length(tt)
        H♢ = SamplePath(tt, zeros(S, N)) 
        V = SamplePath(tt, zeros(T, N)) 
        gpHinv!(H♢, Pt, h♢)
        gpV!(V, Pt, v)
        new{T,S,R2,R}(P, Pt, tt, H♢.yy, V.yy)
    end
    function GuidedBridge(tt_, P::R, Pt::Union{LinearNoiseAppr, LinearAppr}, v::T, h♢::S = Bridge.outer(zero(v))) where {T,R,S}
        tt = collect(tt_)
        N = length(tt)
        H♢ = SamplePath(tt, zeros(S, N)) 
        V = SamplePath(tt, zeros(T, N)) 
        solvebackwardi!(R3(), (t, K, iP) ->  Bi(iP...)*K + K*Bi(iP...)' - ai(iP...), H♢, h♢, Pt)
        solvebackwardi!(R3(), (t, v, iP) ->  bi(iP[1], v, iP[2]), V, v, Pt)
        new{T,S,typeof(Pt),R}(P, Pt, tt, H♢.yy, V.yy)
    end
end
 
bi(i::Integer, x, P::GuidedBridge) = b(P.tt[i], x, P.Target) + a(P.tt[i], x, P.Target)*(P.H♢[i]\(P.V[i] - x)) 
ri(i::Integer, x, P::GuidedBridge) = P.H♢[i]\(P.V[i] - x)
Hi(i::Integer, x, P::GuidedBridge) = inv(P.H♢[i])

σ(t, x, P::GuidedBridge) = σ(t, x, P.Target)
a(t, x, P::GuidedBridge) = a(t, x, P.Target)
Γ(t, x, P::GuidedBridge) = Γ(t, x, P.Target)
constdiff(P::GuidedBridge) = constdiff(P.Target) && constdiff(P.Pt)
btilde(t, x, P::GuidedBridge) = b(t, x, P.Pt)
atilde(t, x, P::GuidedBridge) = a(t, x, P.Pt)
aitilde(t, x, P::GuidedBridge) = ai(t, x, P.Pt)
bitilde(i, x, P::GuidedBridge) = bi(i, x, P.Pt)

@inline _traceB(t, x, P) = trace(Bridge.B(t, P))
traceB(tt, P) = solve(Bridge.R3(), _traceB, tt, 0.0, P)

lptilde(P::GuidedBridge, u) = logpdfnormal(P.V[1] - u, P.H♢[1]) - traceB(P.tt, P.Pt)

hasbi(::GuidedBridge) = true
hasbitilde(P::GuidedBridge) = hasbi(P.Pt)
hasaitilde(P::GuidedBridge) = hasai(P.Pt)

# fallback for testing
lptilde2(P::GuidedBridge, u) = logpdfnormal(P.V[end] - gpmu(P.tt, u, P.Pt), gpK(P.tt, Bridge.outer(zero(u)), P.Pt))


"""
    gpupdate(H♢, V, L, Σ, v)
    gpupdate(P, L, Σ, v)

Return updated `H♢, V` when observation `v` at time zero with error `Σ` is observed.
"""
# H♢_ = H♢ -  H♢*L'*inv(Σ + L*H♢*L')*L*H♢
# V_ = H♢_ * (L'*inv(Σ)*v  + H♢*V)
function gpupdate(H♢, V, L, Σ, v)
    if all(diag(H♢) .== Inf)
        H♢_ = SMatrix(inv(L' * inv(Σ) * L))
        V_ = (L' * inv(Σ) * L)\(L' * inv(Σ) *  v)
        H♢_, V_
    else
        Z = I - H♢*L'*inv(Σ + L*H♢*L')*L
        Z*H♢, Z*H♢*L'*inv(Σ)*v + Z*V
    end
end
gpupdate(P::GuidedBridge, L, Σ, v) = gpupdate(P.H♢[1], P.V[1], L, Σ, v)

# Alternatives to try
#   KT =  PhiTS*(KS + GP2.H♢[1])*PhiTS'   
#   KT = PhiTS*KS*PhiTS' + KTS 
#   logdet( L*KS*L' + Σ - L*KS*inv(KS + GP2.H♢[1])*KS*L' ) + logdet(KS + GP2.H♢[1]) + 2logdet(PhiTS)
#   logdet( KS + GP2.H♢[1] - KS*L'*inv(L*KS*L' + Σ)*L*KS  ) + logdet(L*KS*L' + Σ ) + 2logdet(PhiTS)
function logdetU(GP1, GP2, L, Σ)
    PhiS = fundamental_matrix(GP1.tt, GP1.Pt)
    PhiTS = fundamental_matrix(GP2.tt, GP2.Pt)
    K =  PhiS*GP1.H♢[1]*PhiS' - GP1.H♢[end]
    H = GP2.H♢[1]
    logdet(inv(K) + L'*inv(Σ)*L + inv(H)) + logdet(Σ) + logdet(H) + logdet(K) + 2logdet(PhiTS)
end


#################################################

struct PBridgeProp{T} <: ContinuousTimeProcess{T}
    Target
    t0; v0; tm; vm; t1; v1
    L; Lt; Σ
    cs::CSpline{T}    
    a
    Γ
    PBridgeProp{T}(Target::ContinuousTimeProcess{T}, t0, v0, tm, vm, t1, v1,  L, Σ, a, cs) where T = 
        new(Target, t0, v0, tm, vm, t1, v1, L, L', Σ, cs, a, inv(a))
end
PBridgeProp(Target::ContinuousTimeProcess{T}, t0, v0, tm, vm, t1, v1, L, Σ, a, cs=CSpline(t0, t1, zero(T))) where {T} = PBridgeProp{T}(Target, t0, v0, tm, vm, t1, v1,  L, Σ, a, cs)
        
h1(t, x, P::PBridgeProp) = P.vm - x - integrate(P.cs, t,  P.tm) 
h2(t, x, P::PBridgeProp) = P.v1 - x - integrate(P.cs, t,  P.t1) 

N(t, P::PBridgeProp) = inv(P.L*P.a*P.Lt*(P.tm - t) + (P.t1 - t)/(P.t1 - P.tm)*P.Σ)
Q(t, P::PBridgeProp) = P.Lt*N(t, P)*P.L 

function b(t, x, P::PBridgeProp) 
    if t >= P.tm
        b(t, x, P.Target) + a(t, x, P.Target)*P.Γ*h2(t, x, P)/(P.t1 -t)
    else    
        b(t, x, P.Target) + a(t, x, P.Target)*(Q(t, P)*h1(t, x, P)  +    (P.Γ - Q(t, P)*(P.tm -t))*h2(t, x, P)/(P.t1 -t))
    end
end
function r(t, x, P::PBridgeProp) 
    if t >= P.tm
        P.Γ*h2(t, x, P)/(P.t1 -t)
    else    
        (Q(t, P)*h1(t, x, P)  +    (P.Γ - Q(t, P)*(P.tm -t))*h2(t, x, P)/(P.t1 -t))
    end
end
function H(t, x, P::PBridgeProp) 
    if t >= P.tm
        P.Γ/(P.t1 - t)
    else    
        P.Γ/(P.t1 - t) + Q(t, P)*(P.t1-P.tm)/(P.t1 - t)
    end
end

function lptilde(P::PBridgeProp) 
	n = N(P.t0, P)*(P.tm-P.t0)
	U = Any[	(P.t1-P.t0)/(P.t1-P.tm)/(P.tm-P.t0)*n 		-n*P.L/(P.t1-P.tm)
			-P.L'*n/(P.t1-P.tm) 				(P.Γ + P.L'*n*P.L*(P.tm-P.t0)/(P.t1-P.tm))/(P.t1-P.t0)]
	ldm = sumlogdiag(chol(U[1,1])') +sumlogdiag(chol(U[2,2] - (U[2,1]*inv(U[1,1])*U[1,2]))')
		 	 				
	mu = [P.L*h1(P.t0, P.v0, P); h2(P.t0, P.v0, P)]
	-length(mu)/2*log(2pi) + ldm - 0.5*dot(mu,U*mu)
end

btilde(t, x, P::PBridgeProp) = P.cs(t)
atilde(t, x, P::PBridgeProp) = P.a
σ(t, x, P::PBridgeProp) = σ(t, x, P.Target)
a(t, x, P::PBridgeProp) = a(t, x, P.Target)
constdiff(P::PBridgeProp) = constdiff(P.Target)


#####################


struct FilterProp{T} <: ContinuousTimeProcess{T}
    Target
    t0; v0; t1; v1
    L; Lt; Σ
    cs
    a
    Γ
    FilterProp{T}(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1,  L, Σ, a, cs) where T = 
        new(Target, t0, v0, t1, v1, L, L', Σ, cs, a, inv(a))
end
FilterProp(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1,  L, Σ, a, cs=CSpline(t0, t1, zero(T))) where {T} = FilterProp{T}(Target, t0, v0, t1, v1,  L, Σ, a, cs)
        
h(t,x, P::FilterProp) = P.v1 - x - integrate(P.cs, t, P.t1)

H(t, P::FilterProp) = P.Lt*inv(P.L*P.a*P.Lt*(P.t1 -t) + P.Σ)*P.L

function b(t, x, P::FilterProp) 
    b(t, x, P.Target) + a(t, x, P.Target)*r(t, x, P)
end
function r(t, x, P::FilterProp) 
       H(t, P)*h(t, x, P)
end

btilde(t, x, P::FilterProp) = P.cs(t)
atilde(t, x, P::FilterProp) = P.a
σ(t, x, P::FilterProp) = σ(t, x, P.Target)
a(t, x, P::FilterProp) = a(t, x, P.Target)
constdiff(P::FilterProp) = constdiff(P.Target)

function bderiv(t, x, P::FilterProp) 
    assert(constdiff(P))
    bderiv(t, x, P.Target) - a(t, x, P.Target)*H(t, P)
end    

################################################################


struct DHBridgeProp{T} <: ContinuousTimeProcess{T}
    Target
    t0; v0::T; t1; v1::T
    DHBridgeProp{T}(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1) where T = 
        new(Target, t0, v0, t1, v1)

end
DHBridgeProp(Target::ContinuousTimeProcess{T}, t0, v0, t1, v1) where {T} = DHBridgeProp{T}(Target, t0, v0, t1, v1)

b(t, x, P::DHBridgeProp) = (P.v1 - x )/(P.t1 - t)
σ(t, x, P::DHBridgeProp) = σ(t, x, P.Target)
a(t, x, P::DHBridgeProp) = a(t, x, P.Target)
Γ(t, x, P::DHBridgeProp) = Γ(t, x, P.Target)
constdiff(P::DHBridgeProp) = constdiff(P.Target)

function llikelihood(Xcirc::SamplePath{T}, P::DHBridgeProp{T}) where T
    tt = Xcirc.tt
    xx = Xcirc.yy

    som::Float64 = 0.
    N = length(tt)
    for i in 1:N-1 #skip last value, summing over n-1 elements
        s = tt[i]
        sh = tt[i+1]
        x = xx[i]
        xh = xx[i+1] 
        m = b(s,x,P.Target)
        G = Γ(s,x,P.Target)
        Gh = Γ(sh,xh,P.Target)
        
        som += dot(m,G*(xh - x - 0.5*m*(sh-s))) # girsanov(Xcirc, P.Target, Wiener{Float64}())
        if i < N-1 
            y = xh - P.v1
            som -= 0.5*dot(y, (Gh-G)*y)/(P.t1 - tt[i+1])
        end
    end
    som
end

function lptilde(P::DHBridgeProp{T}) where T 
    dv = P.v1-P.v0
    -length(P.v1)/2*log(2pi*(P.t1-P.t0)) -0.5*logdet(a(P.t1,P.v1,P)) - (0.5/(P.t1-P.t0))*dot(dv, Γ(P.t0,P.v0,P)*dv)
end




################################################################

# using left approximation
function llikelihoodleft(Xcirc::SamplePath{T}, Po::Union{GuidedProp{T},BridgeProp{T},PBridgeProp{T},FilterProp{T}}) where T
    tt = Xcirc.tt
    xx = Xcirc.yy

    som::Float64 = 0.
    for i in 1:length(tt)-1 #skip last value, summing over n-1 elements
        s = tt[i]
        x = xx[i]
        r = Bridge.r(s, x, Po)
        som += (dot(b(s,x, Po.Target) - btilde(s,x, Po), r)  ) * (tt[i+1]-tt[i])
        if !constdiff(Po)
            som -= 0.5*trace((a(s,x, Po.Target) - atilde(s, x, Po))*(H(s,x,Po) -  r*r')) * (tt[i+1]-tt[i])
        end
    end
    som
end

# modern implementation 
# using left approximation
function llikelihood(::LeftRule, Xcirc::SamplePath, Po::GuidedBridge; skip = 0) 
    tt = Xcirc.tt
    xx = Xcirc.yy

    som::Float64 = 0.
    for i in 1:length(tt)-1-skip #skip last value, summing over n-1 elements
        s = tt[i]
        x = xx[i]
#        x2 = xx[i+1]
        r = Bridge.ri(i, x, Po)
#        r2 = Bridge.ri(i+1, x2, Po)
        
        if hasbitilde(Po)
            som += dot( b(s, x, Po.Target) - bitilde(i, x, Po), r ) * (tt[i+1]-tt[i])
        else
            som += dot(b(s, x, Po.Target) - btilde(s, x, Po), r ) * (tt[i+1]-tt[i])
        end    
        if !constdiff(Po)
            H = Hi(i, x, Po)
            if hasaitilde(Po)
                som -= 0.5*trace( (a(s, x, Po.Target) - aitilde(i, x, Po))*(H) ) * (tt[i+1]-tt[i])
                som += 0.5*( r'*(a(s, x, Po.Target) - aitilde(i, x, Po))*r ) * (tt[i+1]-tt[i])
            else
                som -= 0.5*trace( (a(s, x, Po.Target) - atilde(s, x, Po))*(H) ) * (tt[i+1]-tt[i])
                som += 0.5*( r'*(a(s, x, Po.Target) - atilde(s, x, Po))*r ) * (tt[i+1]-tt[i])
            end
        end
    end
    som
end



#using trapezoidal rule
function llikelihoodtrapez(Xcirc::SamplePath{T}, Po::Union{GuidedProp{T},BridgeProp{T},PBridgeProp{T},FilterProp{T}}) where T
    tt = Xcirc.tt
    xx = Xcirc.yy

    som::Float64 = 0.
    i = 1
    s = tt[i]
    x = xx[i]
    r = Bridge.r(s, x, Po)
    som += 0.5*(dot(b(s,x, Po.Target) - btilde(s,x, Po), r)  ) * (tt[i+1]-tt[i])
    if !constdiff(Po)
        som -= 0.25*trace( (a(s,x, Po.Target) - atilde(s, x, Po))*(H(s,x,Po) -  r*r') ) * (tt[i+1]-tt[i])
    end

    for i in 2:length(tt)-1 #skip last value, summing over n-1 elements
        s = tt[i]
        x = xx[i]
        r = Bridge.r(s, x, Po)
        som += 0.5*( dot(b(s,x, Po.Target) - btilde(s,x, Po), r) ) * (tt[i+1]-tt[i-1])
        if !constdiff(Po)
            som -= 0.25*trace( (a(s,x, Po.Target) - atilde(s, x, Po))*(H(s,x,Po) -  r*r') ) * (tt[i+1]-tt[i-1])
        end
    end
    som
end
llikelihood(Xcirc::SamplePath{T}, Po::Union{GuidedProp{T},BridgeProp{T},PBridgeProp{T},FilterProp{T}}) where {T} = llikelihoodleft(Xcirc, Po)
#llikelihood{T}(Xcirc::SamplePath{T}, Po::Union{GuidedProp{T},BridgeProp{T},PBridgeProp{T},FilterProp{T}}) = llikelihoodtrapez(Xcirc, Po) 

