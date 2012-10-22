
module Jekyll::Convertible

  def compressOutput
    self.output = StringIO.new.tap do |io|
      gz = Zlib::GzipWriter.new(io)
      begin
        gz.write(HtmlPress.press self.output)
      ensure
        gz.close
      end
    end.string
  end
end

module MySite_Server

  class Site < Jekyll::Site

    STATUS = {
      :initializing => "initializing",
      :ready => "ready",
      :generating => "generating",
      :updating => "updating"
    }

    attr_accessor :datasources, :pagemap
    attr_reader :status

    def initialize(options)
      super(options)
      @status = STATUS[:initializing]
      self.pagemap = Hash.new

      self.datasources = MySite_Server::DataSource.subclasses.select do |c|
        !self.safe || c.safe
      end.map do |c|
        c.new(self, self.config)
      end

      init
    end

    def init
      self.reset
      self.read
      self.static_files = []
      self.generate
      self.update
    end

    def update
      if(@status != STATUS[:initializing])
        @status = updating
      end
      getData do
        @status = STATUS[:generating]
        self.generateSite
        self.generateMap
      end
      @status = STATUS[:ready]
    end

    def getData
      req_count = self.datasources.length
      self.datasources.each do |datasource|
        datasource.get do |data|
          self.config = self.config.deep_merge(data)
          datasource.preRender if datasource.respond_to?(:preRender)
          req_count-=1
          if req_count == 0 then
            yield
          end
        end
      end
    end

    def generateSite
      self.render
      self.datasources.each do |datasource|
        datasource.postRender if datasource.respond_to?(:postRender)
      end
      self.cleanup
    end

    def genrateMapFor(page)
      if page.data["mySite_redirect"]
      elsif page.data["mySite_proxy"]
      else
        page.compressOutput
        @pagemap[page.destination("")] = {
          :etag        => Digest::SHA1.hexdigest(page.output),
          :body        => page.output
        }
      end
    end

    def generateMap
      self.posts.each do |post|
        genrateMapFor post
      end
      self.pages.each do |page|
        genrateMapFor page
      end
    end

    def getResponse(url)
      url = File.join("/", url)
      @pagemap[url] || @pagemap["#{url}/"] || @pagemap[File.join(url, "index.html")] || @pagemap[File.join(url, "index.htm")]
    end

  end
end