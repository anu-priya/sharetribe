class Api::ListingsController < Api::ApiController

  before_filter :authenticate_person!, :except => [:index, :show]
  # TODO limit visibility of listings based on the visibility rules
  # It requires to authenticate the user but also allow unauthenticated access to above methods
  
  def index
    @page = params["page"] || 1
    @per_page = params["per_page"] || 50
    
    query = params.slice("category", "listing_type")
    
    if params["status"] == "closed"
      query["open"] = false
    elsif params["status"] == "all"
      # leave "open" out totally to return all statuses
    else
      query["open"] = true #default
    end
    
    if params["community_id"]
      @listings = Community.find(params["community_id"]).listings.where(query).order("created_at DESC").paginate(:per_page => @per_page, :page => @page)
    else
      @listings = Listing.where(query).order("created_at DESC").paginate(:per_page => @per_page, :page => @page)
    end
    
    @total_pages = @listings.total_pages
    respond_with @listings
  end

  def show
    @listing = Listing.find_by_id(params[:id])
    if @listing.nil?
      response.status = 404
      render :json => ["No listing found with given ID"] and return
    end
    respond_with @listing
  end

  def create
    
    # Set locations correctly if provided in params
    if params["latitude"] || params["address"]
      params.merge!({"origin_loc_attributes" => {"latitude" => params["latitude"], 
                                                 "longitude" => params["longitude"], 
                                                 "address" => params["address"], 
                                                 "google_address" => params["address"], 
                                                 "location_type" => "origin_loc"}})
      
      if params["destination_latitude"] || params["destination_address"]
        params.merge!({"destination_loc_attributes" => {"latitude" => params["destination_latitude"], 
                                                        "longitude" => params["destination_longitude"], 
                                                        "address" => params["destination_address"], 
                                                        "google_address" => params["destination_address"], 
                                                        "location_type" => "destination_loc"}})
      end
    end
    
    
    @listing = Listing.new(params.slice("title", 
                                        "description", 
                                        "category", 
                                        "share_type", 
                                        "listing_type", 
                                        "visibility",
                                        "origin",
                                        "destination",
                                        "origin_loc_attributes",
                                        "destination_loc_attributes"
                                        ).merge({"author_id" => current_person.id, 
                                                 "listing_images_attributes" => {"0" => {"image" => params["image"]} }}))
    
    @community = Community.find(params["community_id"])
    if @community.nil?
      response.status = 400
      render :json => ["community_id parameter missing, or no community found with given id"] and return
    end
    
    if current_person.member_of?(@community)
      @listing.communities << @community
    else
      response.status = 400
      render :json => ["The user is not member of given community."] and return
    end
    
    if @listing.save
      Delayed::Job.enqueue(ListingCreatedJob.new(@listing.id, @community.full_domain))
      response.status = 201 
      respond_with(@listing)
    else
      response.status = 400
      render :json => @listing.errors.full_messages and return
    end
    
  end

end