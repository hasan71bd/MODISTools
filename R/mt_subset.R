#' Download MODIS Land Products subsets
#'
#' Download a MODIS Land Products Subset product
#' for a given point location buffered with a given amount of kilometers
#' left-right, top-bottom for a given location (provided as latitude and
#' longitude values).
#'
#' @param product a valid MODIS product name
#' @param band band or bands (as a character vector) to download
#' @param lat latitude in decimal degrees
#' @param lon longitude in decimal degrees
#' @param start start date
#' @param end end date
#' @param km_lr km left-right to sample (rounded to the nearest integer)
#' @param km_ab km above-below to sample (rounded to the nearest integer)
#' @param site_id site id (overides lat / lon)
#' @param network the network for which to generate the site list,
#' when not provided the complete list is provided
#' @param site_name arbitrary site name used in writing data to file
#' (default = sitename)
#' @param out_dir path where to store the data if writing to disk
#' (default = tempdir())
#' @param internal should the data be returned as an internal data structure
#' \code{TRUE} or \code{FALSE} (default = \code{TRUE})
#' @param progress show download progress
#' @return A data frame combining meta-data and actual data values.
#' @seealso \code{\link[MODISTools]{mt_sites}}
#' \code{\link[MODISTools]{mt_dates}} \code{\link[MODISTools]{mt_bands}}
#' \code{\link[MODISTools]{mt_products}}
#' \code{\link[MODISTools]{mt_batch_subset}}
#' @export
#' @examples
#'
#' \donttest{
#' # list all available MODIS Land Products Subsets products
#' # download data
#' subset <- mt_subset(product = "MOD11A2",
#'                         lat = 40,
#'                         lon = -110,
#'                         band = "LST_Day_1km",
#'                         start = "2004-01-01",
#'                         end = "2004-03-31",
#'                         progress = FALSE)
#'  head(subset)
#'}

mt_subset <- function(
  product,
  band,
  lat,
  lon,
  start = "2000-01-01",
  end = format(Sys.time(),"%Y-%m-%d"),
  km_lr = 0,
  km_ab = 0,
  site_id,
  network,
  site_name = "sitename",
  out_dir = tempdir(),
  internal = TRUE,
  progress = TRUE
  ){

  # error trap missing coordinates or site id
  if (missing(site_id) & (missing(lat) | missing(lon)) ){
    stop("please specify coordinates, or a valid site ID...")
  }

  # check if site_id is valid
  if(!missing(site_id)){
    if(missing(network)){

      # load all sites
      sites <- MODISTools::mt_sites()

      # check if the site id is valid
      if (!(site_id %in% sites$siteid)){
        stop("please specify a valid site id...")
      }
    } else {

      # load all sites
      sites <- MODISTools::mt_sites(network = network)

      # check if the site id is valid
      if (!(site_id %in% sites$network_siteid)){
        stop("please specify a valid site id...")
      }
    }
  }

  # load all products
  products <- MODISTools::mt_products()$product

  # error trap product
  if (missing(product) | !(product %in% products) ){
    stop("please specify a product, or check your product name...")
  }

  # load all bands for product
  bands <- mt_bands(product)

  # error trap band
  if (missing(band) | !all(band %in% bands$band) ){
    stop("please specify a band, or check your product band combination ...")
  }

  # switch url in case of siteid
  if (missing(site_id)){
    url <- paste(mt_server(),
                  product,
                  "subset",
                 sep = "/")

    # grab all available dates
    dates <- MODISTools::mt_dates(product = product,
                                  lat = lat,
                                  lon = lon)
  } else {
    if(missing(network)){
      url <- paste(mt_server(),
                    product,
                    site_id,
                    "subset",
                   sep = "/")

      # grab all available dates
      dates <- MODISTools::mt_dates(
        product = product,
        site_id = site_id)
    } else {
      url <- paste(mt_server(),
                   product,
                   network,
                   site_id,
                   "subset",
                   sep = "/")

      # grab all available dates
      dates <- MODISTools::mt_dates(
        product = product,
        network = network,
        site_id = site_id)
    }

    lat <- NULL
    lon <- NULL
  }

  # convert to date object for easier handling
  dates$calendar_date <- as.Date(dates$calendar_date)

  # subset the dates
  dates <- dates[which(dates$calendar_date <= as.Date(end) &
           dates$calendar_date >= as.Date(start)),]

  # check if something remains
  if (nrow(dates) == 0){
    stop("No data points exist for the selected date range...")
  }

  # list breaks, for downloads in chunks
  breaks <- seq(1, nrow(dates), 10)

  # grab site name
  site <- ifelse(missing(site_id), site_name, site_id)

  # create a complete list of the data
  complete_data <- lapply(band, function(band_name){

    # start progress bar chuncks
    if(progress){
      message("Downloading chunks:")
      env <- environment()
      counter <- 0
      pb <- utils::txtProgressBar(
        min = 0,
        max = length(breaks),
        style = 3
        )
    }


    # loop over all 10 value breaks
    subset_data <- lapply(breaks, function(b){

      # grab last date for subset
      if(b == breaks[length(breaks)]){
        end_date <-dates$modis_date[nrow(dates)]
      } else {
        end_date <- dates$modis_date[b+9]
      }

      # construct the query to be served to the server
      query <- list("latitude" = lat,
                    "longitude" = lon,
                    "band" = band_name,
                    "startDate" = dates$modis_date[b],
                    "endDate" = end_date,
                    "kmAboveBelow" = round(km_ab),
                    "kmLeftRight" = round(km_lr))

      # try to download the data
      json_chunk <- httr::RETRY(verb = "GET", 
                                url = url,
                                query = query,
                                httr::write_memory(),
                                terminate_on = c(403, 404))

      # trap errors on download, return a detailed
      # API error statement
      if (httr::http_error(json_chunk)){
        warning(httr::content(json_chunk), call. = FALSE)
        return(NULL)
      }

      # check the content of the response
      if (httr::http_type(json_chunk) != "application/json") {
        warning("API did not return json...", call. = FALSE)
        return(NULL)
      }

      # grab content from cached json chunk
      chunk <- jsonlite::fromJSON(httr::content(json_chunk, "text",
                                                encoding = "UTF-8"),
                                  simplifyVector = TRUE)

      # set progress bar
      if(progress){
        tmp <- get("counter", envir = env)
        assign("counter", tmp + 1 ,envir = env)
        utils::setTxtProgressBar(get("pb", envir = env), tmp + 1)
      }

      # return data
      return(chunk)
    })

    # close progress bar
    if(progress){
      close(pb)
    }

    # split out a header including
    # additional ancillary data
    header <- subset_data[[1]][!(names(subset_data[[1]]) %in%
                                     c("header","subset"))]
    header$site <- site
    header$product <- product
    header$start <- start
    header$end <- end
    header$cellsize <- as.character(header$cellsize)

    # This is a check on the complete nature of the retrieved data
    # the process will not stall on errors occur in the download
    # process but just return NULL, these are trapped here and
    # reported as complete TRUE/FALSE in the header or the returned
    # object. Using this flag one can decide to reprocess.
    header$complete <- !any(unlist(lapply(subset_data, is.null)))


    # reshape the data converting it to a tidy data frame
    # data will be reported row wise
    subset_data <- do.call("rbind",
                           lapply(subset_data,
                                  function(x)x$subset))
    pixels <- do.call("rbind",
                      subset_data$data)
    colnames(pixels) <- seq_len(ncol(pixels))

    # remove old nested list data and substitute with columns
    subset_data <- cbind(subset_data[,!(names(subset_data) %in% "data")],
                              pixels)

    subset_data <- stats::reshape(subset_data,
                           varying = grep("[0-9]",names(subset_data)),
                           direction = "long",
                           timevar = "pixel",
                           v.names = "value")

    # drop the id column
    subset_data <- subset_data[ , !(names(subset_data) %in% "id")]

    # combine header with the data, this repeats
    # some meta-data but makes file handling easier
    subset_data <- data.frame(header, subset_data,
                              stringsAsFactors = FALSE)

    # drop duplicate band column
    subset_data <- subset_data[ , !(names(subset_data) %in% "band.1")]


    # return a nested list with all data
    # to workspace or to file
    if (internal){
      return(subset_data)
    } else {
      # format filename
      filename <- sprintf("%s/%s_%s_%s_%s%s.csv",
                          path.expand(out_dir),
                          header$site,
                          header$product,
                          header$band,
                          header$start,
                          header$end)

      # write file to disk
      utils::write.table(subset_data,
                         filename,
                         quote = FALSE,
                         row.names = FALSE,
                         col.names = TRUE,
                         sep = ",")
    }
  })

 # return a larger tidy dataframe by
 # row binding list elements
 return(do.call("rbind", complete_data))

}
