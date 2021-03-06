module GLVisualizeCI

import GitHub, HttpCommon

dir(paths...) = normpath(joinpath(dirname(@__FILE__), "..", paths...))

function push_status(pr, commit)
    try
        repo = LibGit2.GitRepo(GLVisualizeCI.dir())
        LibGit2.fetch(repo)
        LibGit2.add!(repo, ".")
        LibGit2.commit(repo, "update $pr $commit")
        LibGit2.push(repo, refspecs = ["refs/heads/master"])
    catch e
        warn("couldn't update report for $pr: $e")
    end
end


function report_url(ci, repo, pr)
    "https://github.com/SimiDCI/GLVisualizeCI.jl/blob/master/reports/$ci/$repo/$pr"
end


gitclone!(repo, path) = run(`git clone https://github.com/$(repo).git $(path)`)




function test_pr(package, repo, pr)
    mktempdir() do path
        cd(homedir()) # make sure, we're in a concrete folder
        # init a new julia package repository
        ENV["JULIA_PKGDIR"] = path
        Pkg.init()

        builddir = Pkg.dir(package)
        gitclone!(repo, builddir)
        cd(builddir)
        # Fetch current PR
        try
           run(`git fetch --quiet origin +refs/pull/$(pr)/merge:`)
        catch
           # if there's not a merge commit on the remote (likely due to
           # merge conflicts) then fetch the head commit instead.
           run(`git fetch --quiet origin +refs/pull/$(pr)/head:`)
        end
        run(`git checkout --quiet --force FETCH_HEAD`)
        Pkg.add("GLVisualize") # this checks out the dependencies after a fetch
        Pkg.build("GLVisualize")
        julia_exe = Base.julia_cmd()
        logstd = ENV["CI_REPORT_DIR"] * "/log_sttd.txt"
        logsterr = ENV["CI_REPORT_DIR"] * "/log_sterr.txt"
        testcmd = `$julia_exe -e $("Pkg.test(\"$package\", coverage = true)")`
        coveragecmd = `$julia_exe $(dir("src", "submit_coverage.jl"))`
        try
            run(pipeline(testcmd, stdout = `tee $logstd`, stderr = `tee $logsterr`))
            run(pipeline(coveragecmd, stdout = `tee $logstd`, stderr = `tee $logsterr`))
        catch
            println("Test not succesful!")
            return false
        end
        return true
    end
end


function handle_event(name, event, auth)
    kind, payload, repo = event.kind, event.payload, event.repository

    if kind == "pull_request" && payload["action"] != "closed"
        sha = event.payload["pull_request"]["head"]["sha"]
        pr = string(event.payload["pull_request"]["number"])
        package, jl = splitext(get(repo.name))

        target_url = report_url(name, package, pr)
        @show target_url

        path = dir("reports", name)
        isdir(path) || mkdir(path)
        path = dir("reports", name, package)
        isdir(path) || mkdir(path)
        path = dir("reports", name, package, pr)
        isdir(path) || mkdir(path)

        push_status(pr, sha)

        GitHub.create_status(repo, sha; auth = auth, params = Dict(
            "state" => "pending",
            "context" => name,
            "description" => "Running CI...",
            "target_url" => target_url
        ))
        success = false
        try
            ENV["CI_REPORT_DIR"] = path
            ENV["CI"] = "true"
            success = test_pr(package, get(repo.full_name), pr)
            push_status(pr, sha)
        catch err
            GitHub.create_status(repo, sha; auth = auth, params = Dict(
                "state" => "error",
                "context" => name,
                "description" => "Error!",
                "target_url" => target_url
            ))
            return HttpCommon.Response(500)
        end
        GitHub.create_status(repo, sha; auth = auth, params = Dict(
            "state" => success ? "success" : "failure",
            "context" => name,
            "description" => "Build has finished.",
            "target_url" => target_url
        ))
        return HttpCommon.Response(202, "success")
    else
        return HttpCommon.Response(500)
    end
end

function start(name, func = handle_event;
        host = IPv4(128, 30, 87, 54),
        port = 8000,
        myrepos = [GitHub.Repo("JuliaGL/GLVisualize.jl")],
        myauth = GitHub.authenticate(ENV["GITHUB_AUTH"]),
        mysecret = ENV["GITHUB_SECRET"],
        myevents = ["pull_request"]
    )
    listener = GitHub.EventListener(
        event-> handle_event(name, event, myauth),
        auth = myauth,
        secret = mysecret,
        repos = myrepos,
        events = myevents
    )
    GitHub.run(listener, host = host, port = port)
end

end # module
