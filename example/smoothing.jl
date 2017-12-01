
#module Visualize
#using Bridge, PyPlot, StaticVector
#end

using Bridge, StaticArrays, Bridge.Models
const R = ℝ
srand(2)

iterations = 5000
rho = 0.02 # 1 - rho is AR(1) coefficient of Brownian motion valued random walk  
independent = false # independent proposals
adaptive = true # adaptive proposals
adaptit = 1000 # adapt every `it`th step
adaptmax = iterations
cheating = false # take a posteriori good value of Pt
direction = (:nothing, :backward)[1] # influences the starting value of Pt

partial = true

πH = 2000. # prior

t = 1.0
T = 5.00
n = 50001 # total imputed length
m = 100 # number of segments
M = div(n-1,m)
skippoints = 2
dt = (T-t)/(n-1)
tt = t:dt:T
si = 3.
# 10, 20, 8/3 srand(2)
P = Bridge.Models.Lorenz(ℝ{3}(10, 28, 8/3), ℝ{3}(si,si,si))
P2 = Psmooth = Bridge.Models.Lorenz(ℝ{3}(10, 28, 8/3), ℝ{3}(0,0,0))


x0 = Models.x0(P)
#x0 =  ℝ{3}(6, 0, 2)

W = sample(tt, Wiener{ℝ{3}}())
X = SamplePath(tt, zeros(ℝ{3}, length(tt)))
Bridge.solve!(Euler(), X, x0, W, P)
W = sample(tt, Wiener{ℝ{3}}())
X2 = SamplePath(tt, zeros(ℝ{3}, length(tt)))
Bridge.solve!(Euler(), X2, x0, W, P2)


Xtrue = copy(X)

# Observation scheme and subsample
_pairs(collection) = Base.Generator(=>, keys(collection), values(collection))
SV = ℝ{3}
SM = typeof(one(Bridge.outer(zero(SV))))

if !partial
    L = I
    Σ = SDiagonal(50., 1., 1.)
    lΣ = chol(Σ)'
    RV = SV
    RM = SM
 
    V = SamplePath(collect(_pairs(Xtrue))[1:M:end])
    map!(y -> L*y + lΣ*randn(RV), V.yy, V.yy)
else 
    L = @SMatrix [0.0 1.0 0.0; 0.0 0.0 1.0]
    Σ = SDiagonal(1., 1.)
    lΣ = chol(Σ)'
    RV = ℝ{2}
    RM = typeof(one(Bridge.outer(zero(RV))))
 
    V_ = SamplePath(collect(_pairs(Xtrue))[1:M:end])
    V = SamplePath(V_.tt, map(y -> L*y + lΣ*randn(RV), V_.yy))

end
XX = Vector{typeof(X)}(m)
XXmean = Vector{typeof(X)}(m)
XXᵒ = Vector{typeof(X)}(m)
WW = Vector{typeof(W)}(m)
WWᵒ = Vector{typeof(W)}(m)


# Create linear noise approximations


TPt = Bridge.LinearNoiseAppr{Bridge.Models.Lorenz,StaticArrays.SDiagonal{3,Float64},SVector{3,Float64}}
TPᵒ = Bridge.GuidedBridge{SVector{3,Float64},StaticArrays.SArray{Tuple{3,3},Float64,2,9},Bridge.LinearNoiseAppr{Bridge.Models.Lorenz,StaticArrays.SDiagonal{3,Float64},SVector{3,Float64}},Bridge.Models.Lorenz}


Pt = Vector{TPt}(m)
Pᵒ = Vector{TPᵒ}(m)

H♢, v = Bridge.gpupdate(πH*one(SM), zero(SV), L, Σ, V.yy[end])

for i in m:-1:1
    XX[i] = SamplePath(X.tt[1 + (i-1)*M:1 + i*M], X.yy[1 + (i-1)*M:1 + i*M])
    WW[i] = SamplePath(W.tt[1 + (i-1)*M:1 + i*M], W.yy[1 + (i-1)*M:1 + i*M])
    
    if cheating # short-cut, take v later
        a_ = Bridge.a(XX[i].tt[end], XX[i].yy[end], P)
        Pt[i] = Bridge.LinearNoiseAppr(XX[i].tt, P, XX[i].yy[end], a_, direction)
    else
        a_ = Bridge.a(XX[i].tt[end], v, P)
        Pt[i] = Bridge.LinearNoiseAppr(XX[i].tt, P, v, a_, direction) 
    end 
    Pᵒ[i] = Bridge.GuidedBridge(XX[i].tt, P, Pt[i], v, H♢)
    H♢, v = Bridge.gpupdate(Pᵒ[i], L, Σ, V.yy[i])
end
 

π0 = Bridge.Gaussian(v, H♢)

y = π0.μ
for i in 1:m
    sample!(WW[i], Wiener{ℝ{3}}())
    y = Bridge.bridge!(XX[i], y, WW[i], Pᵒ[i])
end
XXmean = [zero(XX[i]) for i in 1:m]

#X0 = ℝ{3}[]

function smooth(π0, XX, WW, P, Pᵒ, iterations, rho; verbose = true,adaptive = true, adaptmax = iterations, adaptit = 5000, independent = false, hwindow=20)
    m = length(XX)
    rho0 = rho / 2 
    # create workspace
    XXᵒ = deepcopy(XX)
    WWᵒ = deepcopy(WW)
    W = Wiener{valtype(WW[1])}()

    # initialize
    mcstate = [mcstart(XX[i].yy) for i in 1:m]
    acc = 0
    y0 = π0.μ

    for it in 1:iterations

        if adaptive && it < adaptmax && it % adaptit == 0 # adaptive smoothing
            H♢, v = Bridge.gpupdate(πH*one(SM), zero(SV), L, Σ, V.yy[end])            
            for i in m:-1:1
                xx = mcstate[i][1]
                Pt[i].Y.yy[:] += [mean(xx[max(1, j-hwindow):min(end, j+hwindow)]) for j in 1:length(xx)]
                Pt[i].Y.yy[:] /= 2
                Pᵒ[i] = Bridge.GuidedBridge(XX[i].tt, P, Pt[i], v, H♢)
                H♢, v = Bridge.gpupdate(Pᵒ[i], L, Σ, V.yy[i])
            end
            π0 = Bridge.Gaussian(v, H♢)
        end

        #push!(X0, y0)
        if !independent
            y0ᵒ = π0.μ + sqrt(rho0)*(rand(π0) - π0.μ) + sqrt(1-rho0)*(y0 - π0.μ) 
        else
            y0ᵒ = rand(π0) 
        end
        y = y0ᵒ
        for i in 1:m
            sample!(WWᵒ[i], W)
            if !independent
                rho_ = rho * rand()
                WWᵒ[i].yy[:] = sqrt(rho_)*WWᵒ[i].yy + sqrt(1-rho_)*WW[i].yy
            end
            y = Bridge.bridge!(XXᵒ[i], y, WWᵒ[i], Pᵒ[i])
        end


        ll = 0.0
        for i in 1:m
            ll += llikelihood(LeftRule(), XXᵒ[i],  Pᵒ[i]) - llikelihood(LeftRule(), XX[i],  Pᵒ[i])
        end
        print("$it ll $(round(ll,2)) ")

        #if true
        if  rand() < exp(ll) 
            acc += 1
            verbose && print("\t X")
            y0 = y0ᵒ
            for i in 1:m
                XX[i], XXᵒ[i] = XXᵒ[i], XX[i]
                WW[i], WWᵒ[i] = WWᵒ[i], WW[i]
            end
        else 
            verbose && print("\t .")
        end
        verbose && println("\t\t", round.(y0 - x0, 2))
        for i in 1:m
            mcstate[i] = Bridge.mcnext!(mcstate[i],XX[i].yy)
        end
    end
    mcstate, acc
end

mcstates, acc = smooth(π0, XX, WW, P, Pᵒ, iterations, rho;
adaptive = adaptive,
adaptit = adaptit,
adaptmax = adaptmax,
verbose = true, independent = independent)

#V0 = cov(Bridge.mat(X0[end÷2:end]),2)  

# Plot result
include("../extra/makie.jl")

Xmean, Xrot, Xscal = mcsvd3(mcstates)

include("makie.jl")
