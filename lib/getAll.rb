require 'eventmachine'
require 'em-http'
require 'em-http/middleware/json_response'
require 'fiber'

GITHUB_USER = "abhishekmunie"
GITHUB_ORG = "mySite"

$count = 0;
$user = Hash.new
$org = Hash.new

puts "Starting..."

$query_queue = Queue.new

$ConcurrentRequests = 15
$query_count = 0

def getNext
  if $query_count <= $ConcurrentRequests and !$query_queue.empty? then    
    $query_count+=1
    req = $query_queue.deq
    puts "Requesting #{req[:url]}"
      cl = EventMachine::HttpRequest.new(req[:url])
      cl.use EventMachine::Middleware::JSONResponse
      http = cl.get :query => req[:query]

      http.errback {
        puts "Uh oh! could not get #{req[:url]}"
        req[:callback].call(nil, nil, nil) if req[:callback]
        $query_count-=1
        getNext
      }
      http.callback {
        puts "Hurry! got #{req[:url]}"
        req[:callback].call(http.response_header.status, http.response_header, http.response) if req[:callback]
        $query_count-=1
        getNext
      }
  end
end

def getHash(url, query)
  $query_queue.enq({:url=> url, :query=> query, :callback=> Proc.new})
  if $query_count == 0 then
    getNext
  else
    getNext
  end
end

def callback
  $count-=1
  if $count != 0
    puts $count
    return
  end
  EM.stop
  puts "user: #{$user}\norg: #{$org}"
end

def getRepos(repos)
  $count += repos.length * 4
  repos.each do |repo|
    getHash(repo["url"], nil) {|status, header, hash| repo[:details] = hash; callback }
    getHash("#{repo["url"]}/readme", nil) {|status, header, hash| repo[:readme] = hash; callback }
    getHash("#{repo["url"]}/downloads", nil) {|status, header, hash| repo[:downloads] = hash; callback }
    getHash("#{repo["url"]}/collaborators", nil) {|status, header, hash| repo[:collaborators] = hash; callback }
    #repo[:wiki] = Gollum::Wiki.new("#{repo["html_url"]}.wiki.git") if repo["has_wiki"]
  end
end

def getUser
  if $count != 0
    return
  end
  $count+=4

  getHash("https://api.github.com/users/#{GITHUB_USER}", Hash.new) { |status, header, hash| $user[:data] = hash; callback }

  getHash("https://api.github.com/users/#{GITHUB_USER}/repos", Hash.new) do |status, header, hash|
    $user[:repos] = hash
    if hash then
      getRepos hash
    end
    callback
  end

  getHash("https://api.github.com/users/#{GITHUB_USER}/orgs", Hash.new) do |status, header, hash|
    $user[:orgs] = hash
    if hash then
      $count += hash.length
      hash.each do |org|
        getHash(org["url"], nil) { |status, header, hash| org[:details] = hash; callback }
      end
    end
    callback
  end

  getHash("https://api.github.com/users/#{GITHUB_USER}/gists", Hash.new) { |status, header, hash| $user[:gists] = hash; callback }
end

def getOrg
  if $count != 0
    return
  end
  $count+=3

  getHash("https://api.github.com/orgs/#{GITHUB_ORG}", Hash.new) { |status, header, hash| $org[:data] = hash; callback }

  getHash("https://api.github.com/orgs/#{GITHUB_ORG}/repos", Hash.new) do |status, header, hash|
    $org[:repos] = hash
    if hash then
      getRepos hash
    end
    callback
  end

  getHash("https://api.github.com/orgs/#{GITHUB_ORG}/members", Hash.new) do |status, header, hash|
    $org[:members] = hash
    if hash then
      $count += hash.length
      hash.each do |member|
        getHash(member["url"], nil) { |status, header, hash| member[:details] = hash; callback }
      end
    end
    callback
  end
end

EventMachine.run {
  getUser if GITHUB_USER
  getOrg if GITHUB_ORG
}

puts "Completed."
