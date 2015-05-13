#!/usr/bin/env coffee

config = require '../config.json'
mysql = require 'mysql'
async = require 'async'

cox = mysql.createConnection(config.mysql)
cox.connect()

todo = 2

cox.query 'select p.ID, pm.meta_value, p.post_type from wp_posts as p inner join wp_postmeta pm on p.ID = pm.post_id and pm.meta_key = "_wp_attached_file" where p.ID not in (select object_id from wp_geo_mashup_location_relationships) ', (err,rows,fields)->
	todo--
	throw err if err
	ExifImage = require('exif').ExifImage
	geolib = require 'geolib'
	# StringDecoder = require('string_decoder').StringDecoder
	# decoder = new StringDecoder('utf8');
	if rows.length > 0
		async.each rows, (item,callback)->
			try
				new ExifImage {image : config.uploads + '/' + item.meta_value}, (exifErr, exifData)->
					if exifErr
						console.log "exif error", exifErr.message
						callback()
					else
						if exifData.gps? and Object.keys(exifData.gps).length isnt 0
							#console.log exifData.image.Make, exifData.image.Model
							lat = exifData.gps.GPSLatitude[0]+ "°" + exifData.gps.GPSLatitude[1] + "'" + exifData.gps.GPSLatitude[1] + "\""+ " " + exifData.gps.GPSLatitudeRef
							lng = exifData.gps.GPSLongitude[0]+ "°" + exifData.gps.GPSLongitude[1] + "'" + exifData.gps.GPSLongitude[1] + "\""+ " " + exifData.gps.GPSLongitudeRef
							lat = geolib.useDecimal(lat)
							lng = geolib.useDecimal(lng)
							cargoUpdate.push({lat:lat, lng:lng, id:item.ID, type:item.post_type})
							#console.log lat, lng
							callback()
						else
							#console.log "Unable to get GEO from",exifData.image.Make, exifData.image.Model if exifData.image?.Make?
							callback()
							#if exifData.image.Make is "Apple"
								# Neet to implement a raw GEO reader a workaround is to implement the GEO tagging on the WP app, it adds the EXIF for this purpose.

								#console.log exifData.exif, exifData.exif.MakerNote.toString('utf-8')
								#console.log exifData.exif.MakerNote, console.log(decoder.write(exifData.exif.MakerNote))
			catch error
				console.log "catched error",error
				callback()
		,(err)->
			bye()
	else
		bye()

cox.query 'select p.ID, p.post_type, m.meta_key, m.meta_value from wp_posts as p inner join wp_postmeta as m on p.ID = m.post_id where (m.meta_key = "geo_latitude" or m.meta_key = "geo_longitude") and p.ID not in (select object_id from wp_geo_mashup_location_relationships)', (err,rows,fields)->
	todo--
	throw err if err
	if rows.length > 0
		data = {}
		for item in rows
			data[item.ID] = {type:item.post_type} if !data[item.ID]?
			data[item.ID][item.meta_key] = item.meta_value
		for key,val of data
			cargoUpdate.push({lat:parseFloat(val.geo_latitude), lng:parseFloat(val.geo_longitude), id:key, type:val.type})
		#console.log data
		bye()
	else
		bye()

cargoUpdate = async.cargo (tk,cb)->
	job = tk[0]
	console.log "job",job
	cox.query "insert into wp_geo_mashup_locations set ? ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id)", {lat : job.lat, lng : job.lng}, (err, result)->
		if err
			console.log "Unable to create location for ", job.id, err
			cb()
		else
			console.log result
			if result.insertId isnt 0
				cox.query "insert into wp_geo_mashup_location_relationships set ?", {object_name : job.type, object_id : job.id, location_id : result.insertId, geo_date : "CURRENT_DATE()"}, (errRel, resultRel)->
					if (errRel)
						console.log "Unable to create relationship for", job.ID, errRel
					cb()
			else
				cb()
,1

cargoUpdate.drain = ()->
	bye()

bye = ()->
	if todo is 0  and cargoUpdate.length() is 0 and !cargoUpdate.running()
		console.log "all done !"
		cox.end()
		process.exit(0)

