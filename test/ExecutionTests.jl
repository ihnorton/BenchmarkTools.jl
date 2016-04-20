module ExecutionTests

using Base.Test
using BenchmarkTools

seteq(a, b) = length(a) == length(b) == length(intersect(a, b))

#########
# setup #
#########

groups = BenchmarkGroup()
groups["sum"] = BenchmarkGroup(["arithmetic"])
groups["sin"] = BenchmarkGroup(["trig"])
groups["special"] = BenchmarkGroup()

sizes = (5, 10, 20)

for s in sizes
    A = rand(s, s)
    groups["sum"][s] = @benchmarkable sum($A) seconds=3
    groups["sin"][s] = @benchmarkable(sin($s); seconds=1, gctrial=false)
end

groups["special"]["macro"] = @benchmarkable @test(1 == 1)
groups["special"]["kwargs"] = @benchmarkable svds(rand(2, 2), nsv = 1)
groups["special"]["nothing"] = @benchmarkable nothing
groups["special"]["block"] = @benchmarkable begin rand(3) end
groups["special"]["comprehension"] = @benchmarkable [s^2 for s in sizes]

function testexpected(received::BenchmarkGroup, expected::BenchmarkGroup)
    @test length(received) == length(expected)
    @test seteq(received.tags, expected.tags)
    @test seteq(keys(received), keys(expected))
    for (k, v) in received
        testexpected(v, expected[k])
    end
end

function testexpected(trial::BenchmarkTools.Trial, args...)
    @test length(trial) > 1
end

testexpected(b::BenchmarkTools.Benchmark, args...) = true

#########
# tune! #
#########

oldgroups = copy(groups)

for id in keys(groups["special"])
    testexpected(tune!(groups["special"][id]))
end

testexpected(tune!(groups["sin"], verbose = true), groups["sin"])
testexpected(tune!(groups, verbose = true), groups)

oldgroupscopy = copy(oldgroups)

loadevals!(oldgroupscopy, evals(groups))
loadparams!(oldgroups, params(groups))

@test oldgroups == oldgroupscopy == groups

#######
# run #
#######

testexpected(run(groups; verbose = true), groups)
testexpected(run(groups; seconds = 1, verbose = true, gctrial = false), groups)
testexpected(run(groups; verbose = true, seconds = 1, gctrial = false, time_tolerance = 0.10, samples = 2, evals = 2, gcsample = false), groups)

testexpected(run(groups["sin"]; verbose = true), groups["sin"])
testexpected(run(groups["sin"]; seconds = 1, verbose = true, gctrial = false), groups["sin"])
testexpected(run(groups["sin"]; verbose = true, seconds = 1, gctrial = false, time_tolerance = 0.10, samples = 2, evals = 2, gcsample = false), groups["sin"])

testexpected(run(groups["sin"][first(sizes)]))
testexpected(run(groups["sin"][first(sizes)]; seconds = 1, gctrial = false))
testexpected(run(groups["sin"][first(sizes)]; seconds = 1, gctrial = false, time_tolerance = 0.10, samples = 2, evals = 2, gcsample = false))

testexpected(run(groups["sum"][first(sizes)], BenchmarkTools.DEFAULT_PARAMETERS))

###########
# @warmup #
###########

p = params(@warmup @benchmarkable sin(1))

@test p.samples == 1
@test p.evals == 1
@test p.gctrial == false
@test p.gcsample == false

##############
# @benchmark #
##############

type Foo
    x::Int
end

const foo = Foo(-1)

t = @benchmark sin(foo.x) evals=3 samples=10 setup=(foo.x = 0)

@test foo.x == 0
@test params(t).evals == 3
@test params(t).samples == 10

b = @benchmarkable sin(x) setup=(foo.x = -1; x = foo.x) teardown=(@assert(x == -1); foo.x = 1)
tune!(b, tune_samples = false)

@test foo.x == 1
@test params(b).evals > 100
@test params(b).samples == BenchmarkTools.DEFAULT_PARAMETERS.samples

foo.x = 0
tune!(b, tune_samples = true)

@test foo.x == 1
@test params(b).evals > 100
@test params(b).samples > BenchmarkTools.DEFAULT_PARAMETERS.samples

########
# misc #
########

# This should always be 1 if BenchmarkTools.OVERHEAD was tuned correctly
@test time(minimum(@benchmark nothing)) == 1

@test [:x, :y, :z] == BenchmarkTools.collectvars(quote
           x = 1 + 3
           y = 1 + x
           z = (a = 4; y + a)
       end)

end # module
