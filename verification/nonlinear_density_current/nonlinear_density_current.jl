"""
This example sets up a cold bubble perturbation which develops into a non-linear
density current. This numerical test case is described by Straka et al. (1993).
Also see: http://www2.mmm.ucar.edu/projects/srnwp_tests/density/density.html

Straka et al. (1993). "Numerical Solutions of a Nonlinear Density-Current -
    A Benchmark Solution and Comparisons." International Journal for Numerical
    Methods in Fluids 17, pp. 1-22.
"""

using Printf
using Plots
using VideoIO
using FileIO
using Oceananigans
using JULES
using JULES: Π

const km = 1000
const hPa = 100

Lx = 51.2km
Lz = 6.4km

Δ = 100  # grid spacing [m]

Nx = Int(Lx/Δ)
Ny = 1
Nz = Int(Lz/Δ)

grid = RegularCartesianGrid(size=(Nx, Ny, Nz), halo=(2, 2, 2),
                            x=(-Lx/2, Lx/2), y=(-Lx/2, Lx/2), z=(0, Lz))

#####
##### Initial perturbation
#####

gas = IdealGas()
Rᵈ, cₚ, cᵥ = gas.Rᵈ, gas.cₚ, gas.cᵥ
g  = 9.80665
pₛ = 1000hPa
Tₛ = 300

# Define an approximately hydrostatic background state
θ₀(x, y, z) = Tₛ
p₀(x, y, z) = pₛ * (1 - g*z/(cₚ*Tₛ))^(cₚ/Rᵈ)
T₀(x, y, z) = Tₛ*(p₀(x, y, z)/pₛ)^(Rᵈ/cₚ)
ρ₀(x, y, z) = p₀(x, y, z)/(Rᵈ*T₀(x, y, z))

# Define the initial density perturbation
xᶜ, zᶜ = 0km, 2km
xʳ, zʳ = 2km, 2km
L(x, y, z) = sqrt(((x - xᶜ)/xʳ)^2 + ((z - zᶜ)/zʳ)^2)
function ρ′(x, y, z; θᶜ′ = -15.0)
    l = L(x, y, z)
    θ′ = (l <= 1) * θᶜ′ * (1 + cos(π*l))/2
    return -ρ₀(x, y, z) * θ′ / θ₀(x, y, z)
end

# Define initial state
ρᵢ(x, y, z) = ρ₀(x, y, z) + ρ′(x, y, z)
pᵢ(x, y, z) = p₀(x, y, z)
Tᵢ(x, y, z) = pᵢ(x, y, z) / (Rᵈ * ρᵢ(x, y, z))
θᵢ(x, y, z) = Tᵢ(x, y, z) * (pₛ / pᵢ(x, y, z))^(Rᵈ/cₚ)

#####
##### Set up model
#####

model = CompressibleModel(
                      grid = grid,
                  buoyancy = gas,
        reference_pressure = pₛ,
    thermodynamic_variable = ModifiedPotentialTemperature(),
                   tracers = (:Θᵐ,),
                   closure = ConstantIsotropicDiffusivity(ν=0.5, κ=0.5)
)

# Set initial state after saving perturbation-free background
ρ, Θ = model.density, model.tracers.Θᵐ
xC, zC = grid.xC, grid.zC
set!(model.density, ρ₀)
set!(model.tracers.Θᵐ, (x, y, z) -> ρ₀(x, y, z) * θ₀(x, y, z))
ρʰᵈ = ρ.data[1:Nx, 1, 1:Nz]
Θʰᵈ = Θ.data[1:Nx, 1, 1:Nz]
set!(model.density, ρᵢ)
set!(model.tracers.Θᵐ, (x, y, z) -> ρᵢ(x, y, z) * θᵢ(x, y, z))

ρ_plot = contour(model.grid.xC ./ km, model.grid.zC ./ km,
    rotr90(ρ.data[1:Nx, 1, 1:Nz] .- ρʰᵈ), fill=true, levels=10, ylims=(0, 6.4),
    clims=(-0.05, 0.05), color=:balance, aspect_ratio=:equal, dpi=200)
savefig(ρ_plot, "rho_prime_initial_condition.png")

θ_slice = rotr90(Θ.data[1:Nx, 1, 1:Nz] ./ ρ.data[1:Nx, 1, 1:Nz])
Θ_plot = contour(model.grid.xC ./ km, model.grid.zC ./ km, θ_slice,
                 fill=true, levels=10, ylims=(0, 6.4), color=:thermal,
                 aspect_ratio=:equal, dpi=200)
savefig(Θ_plot, "theta_initial_condition.png")

#####
##### Watch the density current evolve!
#####

for n = 1:180
    @printf("t = %.2f s\n", model.clock.time)
    time_step!(model, Δt=0.1, Nt=50)

    xC, yC, zC = model.grid.xC ./ km, model.grid.yC ./ km, model.grid.zC ./ km
    xF, yF, zF = model.grid.xF ./ km, model.grid.yF ./ km, model.grid.zF ./ km

    j = 1
    u_slice = rotr90(model.momenta.ρu.data[1:Nx, j, 1:Nz] ./ model.density.data[1:Nx, j, 1:Nz])
    w_slice = rotr90(model.momenta.ρw.data[1:Nx, j, 1:Nz] ./ model.density.data[1:Nx, j, 1:Nz])
    ρ_slice = rotr90(model.density.data[1:Nx, j, 1:Nz] .- ρʰᵈ)
    θ_slice = rotr90(model.tracers.Θᵐ.data[1:Nx, j, 1:Nz] ./ model.density.data[1:Nx, j, 1:Nz])

    u_title = @sprintf("u, t = %d s", round(Int, model.clock.time))
    pu = heatmap(xC, zC, u_slice, title=u_title, fill=true, levels=10,
        color=:balance, clims=(-20, 20), linewidth=0, xticks = nothing,
        titlefontsize = 10)
    pw = heatmap(xC, zC, w_slice, title="w", fill=true, levels=10,
        color=:balance, clims=(-20, 20), linewidth=0, xticks = nothing,
        titlefontsize = 10)
    pρ = heatmap(xC, zC, ρ_slice, title="rho_prime", fill=true, levels=10,
        color=:balance, clims=(-0.05, 0.05), linewidth=0, xticks = nothing,
        titlefontsize = 10)
    pθ = heatmap(xC, zC, θ_slice, title="theta", fill=true, levels=10,
        color=:oxy, clims=(284, 300), linewidth=0,
        titlefontsize = 10)

    p = plot(pu, pw, pρ, pθ, layout=(4, 1), dpi=300, show=true)
    savefig(p, @sprintf("frames/density_current_%03d.png", n))
end

ρ′_1000 = (model.density.data[1:Nx, 1, 1:Nz] .- ρʰᵈ)
w_1000 = (model.momenta.ρw.data[1:Nx, 1, 1:Nz] ./ model.density.data[1:Nx, 1, 1:Nz])

@printf("ρ′: min=%.2f, max=%.2f\n", minimum(ρ′_1000), maximum(ρ′_1000))
@printf("w:  min=%.2f, max=%.2f\n", minimum(w_1000), maximum(w_1000))

@printf("Rendering MP4\n")
imgs = filter(x -> occursin(".png", x), readdir("frames"))
imgorder = map(x -> split(split(x, ".")[1], "_")[end], imgs)
p = sortperm(parse.(Int, imgorder))
frames = []
for img in imgs[p]
    push!(frames, convert.(RGB, load("frames/$img")))
end
encodevideo("density_current.mp4", frames, framerate = 30)
