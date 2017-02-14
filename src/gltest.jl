using GLVisualize
include(GLVisualize.dir("examples", "ExampleRunner.jl"))
using ExampleRunner
importall ExampleRunner
using GLAbstraction, GLWindow, Colors
using FileIO, GeometryTypes, Reactive, Images

function image_url(path)
    path, name = splitdir(path)
    path, dir = splitdir(path)
    "https://github.com/SimiDCI/GLVisualizeCI.jl/blob/master/reports/$(joinpath(dir, name))?raw=true"
end

function create_mosaic(io, folder, width = 150)
    images = filter(x-> endswith(x, ".jpg"), readdir(folder))
    for im in images
        println(io, """<img src="$(image_url(joinpath(folder, im)))"
            alt="$(im)" width=$(width)px"/>
        """)
    end
end

function test_and_record(full_folder)
    files = [
        "introduction/rotate_robj.jl",
        "introduction/screens.jl",
        "plots/3dplots.jl",
        "plots/lines_scatter.jl",
        "plots/hybrid.jl",
        "camera/camera.jl",
        "gui/color_chooser.jl",
        "gui/image_processing.jl",
        "gui/buttons.jl",
        "gui/fractal_lines.jl",
        "gui/mandalas.jl",
        "plots/drawing.jl",
        "interactive/graph_editing.jl",
        "interactive/mario_game.jl",
        "text/text_particle.jl",
    ]

    map!(x-> GLVisualize.dir("examples", x), files, files)
    files = union(files, ExampleRunner.flatten_paths(GLVisualize.dir("examples")))
    push!(files, GLVisualize.dir("test", "summary.jl"))
    files = unique(normpath.(files))
    # Create an examplerunner, that displays all examples in the example folder, plus
    # a runtest specific summary.
    config = ExampleRunner.RunnerConfig(
        record = false,
        record_image = true,
        files = files,
        thumbnail = false,
        screencast_folder = full_folder,
        resolution = (200, 200)
    )
    GLWindow.set_visibility!(config.rootscreen, false)
    window = config.window
    for path in config.files
        isopen(config.rootscreen) || break
        try
            println(basename(path))
            test_module = ExampleRunner._test_include(path, config)
            ExampleRunner.display_msg(test_module, config)
            GLWindow.poll_glfw()
            GLWindow.poll_reactive()
            yield()
            render_frame(config.rootscreen)
            swapbuffers(config.rootscreen)
            name = basename(path)[1:end-3]
            name = joinpath(config.screencast_folder, name * ".jpg")
            GLWindow.screenshot(config.rootscreen, path = name)
        catch e
            #failed[i] = true
            bt = catch_backtrace()
            ex = CapturedException(e, bt)
            showerror(STDERR, ex)
            config[:success] = false
            config[:exception] = ex
        finally
            empty!(window)
            empty!(config.buttons[:timesignal].actions)
            window.color = RGBA{Float32}(1,1,1,1)
            window.clear = true
            GLVisualize.empty_screens!()
            GLVisualize.add_screen(window) # make window default again!
            for (k, s) in window.inputs
                empty!(s.actions)
            end
            empty!(window.cameras)
            gc()
        end
        yield()
    end
    open(joinpath(full_folder, "report.md"), "w") do io
        failures = filter(config.attributes) do k, dict
            !dict[:success]
        end
        println(io, "### Test Images:")
        create_mosaic(io, full_folder)
        if !isempty(failures)
            println(io, "### Failures:")
            for (k, dict) in failures
                println(io, "file: $k")
                println(io, "$(dict[:exception])")
            end
        else
            println(io, "No failures! :)")
        end
    end

    open(joinpath(full_folder, "message.txt"), "w") do io
        success = count(kd-> kd[2][:success], config.attributes)
        fails = length(config.files) - success
        print(io, "$success tests completed successfully, $fails failed. [Full report](")
        println(io, "https://github.com/SimiDCI/GLVisualizeCI.jl/blob/master/reports/$(joinpath(basename(full_folder), "report.md")))")
    end
end