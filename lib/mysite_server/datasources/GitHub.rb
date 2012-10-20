require 'eventmachine'
require 'em-http'
require 'em-http/middleware/json_response'

module MySite_Server
    
  class Github < DataSource

    attr_reader :name
    
    def initialize(site, config)
      @site = site
      @pages = []
      @templates = Hash.new
      github_USER = config["GitHub"]["user"] || "abhishekmunie"
      github_ORG = config["GitHub"]["org"] || "ASE-Inc"
      
      if github_USER
        @name = @user = MySite_Server::GitHub::User.new(github_USER)
      elsif github_ORG
        @name = @org = MySite_Server::GitHub::Org.new(github_ORG)
      end
    end

    def get
      if @user then
        @user.get do
          if block_given?
            yield({
              "GitHub_User"=> {
                @user.name=> {
                  "details"=> @user.details,
                  "repos"=> @user.repos,
                  "orgs"=> @user.orgs,
                  "gists"=> @user.gists
                }
              }
            })
          end
        end
      elsif @org then
        @org.get do
          if block_given?
            yield({
              "GitHub_Org"=> {
                @org.name=> {
                  "details"=> @org.details,
                  "repos"=> @org.repos,
                  "members"=> @org.members
                }
              }
            })
          end
        end
      end
    end

    def initTemplates
      @site.pages.each do |page|
        url = page.destination("")
        url.slice!("/GitHub")
        case url
        when "/projects/index.html"
          @templates[:projects] = page
        when "/projects/project/index.html"
          @templates[:project] = page
        when "/projects/project/downloads/index.html"
          @templates[:downloads] = page
        when "/organizations/index.html", "/orgs/index.html"
          @templates[:organizations] = page
        when "/organizations/organization/index.html", "/orgs/org/index.html"
          @templates[:organization] = page
        when "/gists/index.html"
          @templates[:gists] = page
        when "/gists/gist/index.html"
          @templates[:gist] = page
        when "/members/index.html"
          @templates[:members] = page
        when "/members/member/index.html"
          @templates[:member] = page
        end
      end
    end

    def generatePage(path, template, payload)
      if @templates[template]
        page = @templates[template].clone
        page.dir = path
        page.instance_variable_set('@payload', payload)
        def page.render(layouts, site_payload)
          site_payload = {"page_github"=> @payload}.deep_merge(site_payload)
          super(layouts, site_payload)
          @payload = nil
        end
        @site.pages << page
      end
    end

    def preRender
      initTemplates
      if @user then
        generatePage("/projects/", :projects, {"repos"=> @user.repos})
        @user.repos.each do |repo|
          generatePage("/projects/#{repo["name"]}/", :project, {"repo"=> repo})
          generatePage("/projects/#{repo["name"]}/downloads/", :downloads, {"repo"=> repo, "downloads"=> repo[:downloads]})
        end
        generatePage("/organizations/", :organizations, {"orgs"=> @user.orgs})
        @user.orgs.each do |org|
          generatePage("/organizations/#{org["login"]}/",:organization, {"org"=> org})
        end
        generatePage("/gists/", :gists, {"gists"=> @user.gists})
        @user.gists.each do |gist|
          generatePage("/gists/#{gist["id"]}/",:gist, {"gist"=> gist})
        end
      elsif @org then
        generatePage("/projects/", :projects, {"repos"=> @org.repos})
        @org.repos.each do |repo|
          generatePage("/projects/#{repo["name"]}/", :project, {"repo"=> repo})
          generatePage("/projects/#{repo["name"]}/downloads/", :downloads, {"downloads"=> repo[:downloads]})
        end
        generatePage("/members/", :members, {"members"=> @org.members})
        @org.members.each do |member|
          generatePage("/members/#{member["login"]}/", :member, {"member"=> member})
        end
      end
    end

    def postRender
      @user = nil
      @org = nil
    end
  end

  module GitHub
    class Account

      attr_accessor :readme_raw
      attr_reader :name

      protected

      attr_writer :name
      
      def initialize
        @query_count = 0
        @query_queue = Queue.new
        @ConcurrentRequests = 15
        @ongoing_count = 0
        @callback_block = nil
      end

      def getNext
        if @ongoing_count <= @ConcurrentRequests and !@query_queue.empty?
          @ongoing_count+=1
          query = @query_queue.deq
          puts "Requesting #{query[:url]}"
          cl = EventMachine::HttpRequest.new(query[:url])
          cl.use query[:middleware] if query[:middleware]
          if query[:query] then
            req = cl.get :query => query[:query]
          else
            req = cl.get
          end
          req.errback {
            puts "Oh! error #{query[:url]}"
            query[:callback].call(nil, nil, nil) if query[:callback]
            @ongoing_count-=1
            getNext
          }
          req.callback {
            puts "Hurry! got #{query[:url]}"
            query[:callback].call(req.response_header.status, req.response_header, req.response) if query[:callback]
            @ongoing_count-=1
            getNext
          }
        end
      end

      def getRAW(url, query = nil, middleware = nil)
        url.slice!(0..7)
        url.slice!("blob/")
        @query_queue.enq({:url=> "https://raw.#{url}", :query=> query, :middleware=>middleware, :callback=> block_given? ? Proc.new : nil})
        getNext
      end

      def getHash(url, query = nil)
        @query_queue.enq({:url=> url, :query=> query, :middleware=>EventMachine::Middleware::JSONResponse, :callback=> block_given? ? Proc.new : nil})
        getNext
      end

      def callback
        @query_count-=1
        if @query_count != 0
          puts @query_count
          return
        end
        if @callback_block then
          @callback_block.call()
        else
          
        end
        #EM.stop
      end

      def getRepos(repos)
        @query_count+= repos.length * 5
        repos.each do |repo|
          getHash(repo["url"]) {|status, header, response| repo["_details"] = response; callback }
          getHash("#{repo["url"]}/contents") {|status, header, response| repo["_contents"] = response; callback }
          getHash("#{repo["url"]}/readme") do |status, header, response|
            repo["_readme"] = response;
            if response and status == 200 then
              if response["_links"]
                @query_count+=1
                getRAW(response["_links"]["html"]) {|status, header, response| repo["_readme"]["_raw"] = response; callback }
              end
            end
            callback
          end
          if repo["has_downloads"]
            getHash("#{repo["url"]}/downloads") {|status, header, response| repo["_downloads"] = response; callback }
          else
            @query_count-=1
          end
          getHash("#{repo["url"]}/collaborators") {|status, header, response| repo["_collaborators"] = response; callback }
          #repo[:wiki] = Gollum::Wiki.new("#{repo["html_url"]}.wiki.git") if repo["has_wiki"]
        end
      end
    end

    class User < Account

      attr_reader :details, :repos, :orgs, :gists

      private

      attr_writer :details, :repos, :orgs, :gists

      public

      def initialize(user)
        super()
        self.name = @User = user
      end

      def get
        if @query_count != 0
          return
        end
        @query_count+=4

        @callback_block = Proc.new if block_given?

        getHash("https://api.github.com/users/#{@User}") { |status, header, response| self.details = response; callback }

        getHash("https://api.github.com/users/#{@User}/repos") do |status, header, response|
          self.repos = response
          if response and status == 200 then
            getRepos response
          end
          callback
        end

        getHash("https://api.github.com/users/#{@User}/orgs") do |status, header, response|
          self.orgs = response
          if response and status == 200 then
            @query_count+= response.length
            response.each do |org|
              getHash(org["url"]) { |status, header, response| org["_details"] = response; callback }
            end
          end
          callback
        end

        getHash("https://api.github.com/users/#{@User}/gists") { |status, header, response| self.gists = response; callback }
      end

    end

    class Org < Account

      attr_reader :details, :repos, :members

      private

      attr_writer :details, :repos, :members

      public

      def initialize(org)
        super()
        self.name = @Org = org
      end

      def get
        if @query_count != 0
          return
        end
        @query_count+=3

        @callback_block = Proc.new if block_given?

        getHash("https://api.github.com/orgs/#{@Org}") { |status, header, response| self.details = response; callback }

        getHash("https://api.github.com/orgs/#{@Org}/repos") do |status, header, response|
          self.repos = response
          if response and status == 200 then
            getRepos response
          end
          callback
        end

        getHash("https://api.github.com/orgs/#{@Org}/members") do |status, header, response|
          self.members = response
          if response and status == 200 then
            @query_count+= response.length
            response.each do |member|
              getHash(member["url"]) { |status, header, response| member["_details"] = response; callback }
            end
          end
          callback
        end
      end

    end

  end

end
