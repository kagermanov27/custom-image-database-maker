module DatabaseMaker
using HTTP
using JSON3
using CSV
using DataFrames

  export make
  function ask_for_query_preference()
    println("Would you like to add queries from terminal or from a local file?")
    println("1) Terminal (first page per each query)")
    println("2) Local File (can define page ranges)")
    println("Enter a number: ")
    answer = readline()
    answer == "1" && read_from_terminal()
    answer == "2" && read_from_file()
  end

  function read_from_terminal()
    println("Enter queries seperated by commas:")
    queries = readline()
    queries = split(queries, ",")
    global queries = DataFrame( q = queries, page_range = fill(0, length(queries)) )
  end

  function read_from_file()
    println("Reading from file...")
    types = Dict(
      :q => String,
      :page_range => String,
    )
    queries = DataFrame(CSV.File("load_new_data.csv"; types))
    global queries = coalesce.(queries, 0)
  end

  function ask_for_cache_preference()
    println("Would you like cached data? (Note that cached searches don't use calls from your account. But if the query is not cached, it'll resort to \"no_cache=true\")")
    println("1) No Cached Searches (true)")
    println("2) Cached Searches (false)")
    println("Enter a number: ")
    answer = readline()
    answer == "1" && global cache_preference = true
    answer == "2" && global cache_preference = false
    println(cache_preference)
  end

  function get_api_key()
    global api_key = read(Base.getpass("Enter your API key:"), String)
  end


  function construct_searches()
    for (index,q) ∈ enumerate(queries[:,:q])
      page = queries[index,:page_range]
      occursin("-", string(page)) ? range_page_number(q, page) : call_serpapi(q, page)
    end
  end

  function range_page_number(q, page)
    page = split(page, "-")
    from = parse(Int,page[1])
    to = parse(Int,page[2])
    for page ∈ from:to
      call_serpapi(q, page)
    end
  end


  function call_serpapi(q, page)
    params = [
      "q"        => q,
      "tbm"      => "isch",
      "ijn"      => page,
      "api_key"  => api_key,
      "no_cache" => cache_preference,
    ]

    uri = "https://serpapi.com/search.json?"

    println("Querying \"q\":\"$(q)\", \"ijn\":\"$(page)\" with \"no_cache\":\"$(cache_preference)\"...")

    results = HTTP.get(uri, query = params)

    results = JSON3.read(results.body)

    results = results[:images_results]

    results = [resulting_image[:original] for resulting_image ∈ results]

    println("Checking if folder and csv exists...")

    folder_name = replace(q, " " => "_")
    folder_name = replace(folder_name, "." => "_")
    check_folder_and_csv(folder_name)
    check_new_links(folder_name, results)
  end

  function check_folder_and_csv(folder_name)
    folder_name ∉ readdir("Datasets") && make_folder_and_csv(folder_name)
  end

  function make_folder_and_csv(folder_name)
    mkdir("Datasets/$(folder_name)")
    initial_csv = DataFrame()
    initial_csv.link = []
    CSV.write("Datasets/$(folder_name)/links.csv", initial_csv)
  end

  function check_new_links(folder_name, results)
    println("Reading links of \"Datasets/$(folder_name)\"")
    types = Dict(
      :link => String,
    )
    global links = DataFrame(CSV.File("Datasets/$(folder_name)/links.csv"; types))

    println("Comparing new links with links of \"Datasets/$(folder_name)\"")
    for result ∈ results
      accepted_filetypes = [".bmp", ".png", ".jpg", ".jpeg", ".png"]
      length(links[:,:link]) ≠ 0 && result ∉  links[:,:link] && any(x->occursin(x,last(result,5)), accepted_filetypes) && append_links(result, folder_name)
      length(links[:,:link]) == 0 && append_links(result, folder_name)
    end

    println("Updating links of \"Datasets/$(folder_name)\"")
    CSV.write("Datasets/$(folder_name)/links.csv", links)
  end

  function append_links(result, folder_name)
    result_row = DataFrame(Dict(:link=>result))
    append!(links, result_row)
    append!(images_to_be_requested, [[result,folder_name]])
  end

  function download_images()
    println("$(length(images_to_be_requested)) images to be downloaded...")
    for image ∈ images_to_be_requested
      uri = image[1]
      folder_name = image[2]
      filename = define_filename(uri, folder_name)
      println("Downloading into \"$(filename)\"...")
      HTTP.download(uri,filename)
      println("---------------------")
    end
    println("Downloaded all images!")
  end

  function define_filename(uri, folder_name)
    filename = readdir("Datasets/$(folder_name)")
    deleteat!(filename, findall(x->x=="links.csv", filename))
    if length(filename) == 0
      filename = "1"
    else
      filename = [parse(Int, split(name,".")[1]) for name ∈ filename]
      filename = maximum(filename) + 1
    end
    extension = last(split(uri,"."))
    filename = "Datasets/$(folder_name)/$(filename).$(extension)"
    return filename
  end

  function make()
    global images_to_be_requested = []
    ask_for_query_preference()
    println("---------------------")
    ask_for_cache_preference()
    println("---------------------")
    get_api_key()
    println("---------------------")
    construct_searches()
    println("---------------------")
    download_images()
  end
end



