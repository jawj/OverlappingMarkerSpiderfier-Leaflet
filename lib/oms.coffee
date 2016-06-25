'use strict'
###* @preserve OverlappingMarkerSpiderfier
https://github.com/jawj/OverlappingMarkerSpiderfier-Leaflet
Copyright (c) 2011 - 2012 George MacKerron
Released under the MIT licence: http://opensource.org/licenses/mit-license
Note: The Leaflet maps API must be included *before* this code
###

# NB. string literal properties -- object.key -- are for Closure Compiler ADVANCED_OPTIMIZATION

return unless this.L?  # return from wrapper func without doing anything

class @OverlappingMarkerSpiderfier
  p = @::  # this saves a lot of repetition of .prototype that isn't optimized away
  p.VERSION = '0.2.6'
  twoPi = Math.PI * 2

  defaultOpts =
    keepSpiderfied: no           # yes -> don't unspiderfy when a marker is selected
    nearbyDistance: 20           # spiderfy markers within this range of the one clicked, in px
  
    circleSpiralSwitchover: 9    # show spiral instead of circle from this marker count upwards
                                     # 0 -> always spiral; Infinity -> always circle
    circleFootSeparation: 25     # related to circumference of circle
    circleStartAngle: 1
    spiralFootSeparation: 28     # related to size of spiral (experiment!)
    spiralLengthStart: 11        # ditto
    spiralLengthFactor: 5        # ditto
   
    legWeight: 1.5
    legColors:
      usual: '#222'
      highlighted: '#f00'
    unspiderfyEvents: ['click', 'zoomend']
    spiderfyMarkerEvent: 'click'
    body:
      color: '#222'
      radius: 3
      opacity: 0.9
      fillOpacity: 0.9

  # Note: it's OK that this constructor comes after the properties, because of function hoisting
  constructor: (@map, opts = {}) ->
    extend(@, defaultOpts, opts)
    @initMarkerArrays()
    @listeners = {}
    if @unspiderfyEvents && @unspiderfyEvents.length
      @map.addEventListener(e, => @unspiderfy()) for e in @unspiderfyEvents
    
  p.initMarkerArrays = ->
    @markers = []
    @markerListeners = []
    @bodies = []
    
  p.addMarker = (marker) ->
    return @ if marker._oms?
    marker._oms = yes
    markerListener = => @spiderListener(marker)
    if @spiderfyMarkerEvent && @spiderfyMarkerEvent.length
      marker.addEventListener(@spiderfyMarkerEvent, markerListener)
    @markerListeners.push(markerListener)
    @markers.push(marker)
    @  # return self, for chaining

  p.getMarkers = -> @markers[0..]  # returns a copy, so no funny business

  p.removeMarker = (marker) ->
    @unspiderfy() if marker._omsData?  # otherwise it'll be stuck there forever!
    i = @arrIndexOf(@markers, marker)
    return @ if i < 0
    markerListener = @markerListeners.splice(i, 1)[0]
    if @spiderfyMarkerEvent && @spiderfyMarkerEvent.length
      marker.removeEventListener(@spiderfyMarkerEvent, markerListener)
    delete marker._oms
    @markers.splice(i, 1)
    @  # return self, for chaining
    
  p.clearMarkers = ->
    @unspiderfy()
    for marker, i in @markers
      markerListener = @markerListeners[i]
      if @spiderfyMarkerEvent && @spiderfyMarkerEvent.length
        marker.removeEventListener(@spiderfyMarkerEvent, markerListener)
      delete marker._oms
    @initMarkerArrays()
    @  # return self, for chaining
        
  # available listeners: click(marker), spiderfy(markers), unspiderfy(markers)
  p.addListener = (event, func) ->
    (@listeners[event] ?= []).push(func)
    @  # return self, for chaining
    
  p.removeListener = (event, func) ->
    i = @arrIndexOf(@listeners[event], func)
    @listeners[event].splice(i, 1) unless i < 0
    @  # return self, for chaining
  
  p.clearListeners = (event) ->
    @listeners[event] = []
    @  # return self, for chaining
  
  p.trigger = (event, args...) ->
    func(args...) for func in (@listeners[event] ? [])
  
  p.generatePtsCircle = (count, centerPt) ->
    circumference = @circleFootSeparation * (2 + count)
    legLength = circumference / twoPi  # = radius from circumference
    angleStep = twoPi / count
    calculatedStartAngle = @circleStartAngle * (Math.PI / 180)
    for i in [0...count]
      angle = calculatedStartAngle + i * angleStep
      new L.Point(centerPt.x + legLength * Math.cos(angle), 
                  centerPt.y + legLength * Math.sin(angle))
  
  p.generatePtsSpiral = (count, centerPt) ->
    legLength = @spiralLengthStart
    angle = 0
    for i in [0...count]
      angle += @spiralFootSeparation / legLength + i * 0.0005
      pt = new L.Point(centerPt.x + legLength * Math.cos(angle), 
                       centerPt.y + legLength * Math.sin(angle))
      legLength += twoPi * @spiralLengthFactor / angle
      pt
  
  p.spiderListener = (marker) ->
    markerSpiderfied = marker._omsData?
    if !@keepSpiderfied
      @unspiderfy() unless markerSpiderfied
    if markerSpiderfied
      @trigger('click', marker)
      return @
    else
      nearbyMarkerData = []
      nonNearbyMarkers = []
      pxSq = @nearbyDistance * @nearbyDistance
      markerPt = @map.latLngToLayerPoint(marker.getLatLng())
      for m in @markers
        continue unless @map.hasLayer(m)
        mPt = @map.latLngToLayerPoint(m.getLatLng())
        if @ptDistanceSq(mPt, markerPt) < pxSq
          nearbyMarkerData.push(marker: m, markerPt: mPt)
        else
          nonNearbyMarkers.push(m)
      if nearbyMarkerData.length is 1  # 1 => the one clicked => none nearby
        @trigger('click', marker)
      else if (nearbyMarkerData.length > 0 && nonNearbyMarkers.length > 0)
        @spiderfy(nearbyMarkerData, nonNearbyMarkers)
      else
        null
  
  p.makeHighlightListeners = (marker) ->
    highlight:   => marker._omsData.leg.setStyle(color: @legColors.highlighted)
    unhighlight: => marker._omsData.leg.setStyle(color: @legColors.usual)
  
  p.spiderfy = (markerData, nonNearbyMarkers) ->
    @spiderfying = yes
    numFeet = markerData.length
    bodyPt = @ptAverage(md.markerPt for md in markerData)
    footPts = if numFeet >= @circleSpiralSwitchover
      @generatePtsSpiral(numFeet, bodyPt).reverse()  # match from outside in => less criss-crossing
    else
      @generatePtsCircle(numFeet, bodyPt)
    lastMarkerCoords = null
    spiderfiedMarkers = for footPt in footPts
      footLl = @map.layerPointToLatLng(footPt)
      nearestMarkerDatum = @minExtract(markerData, (md) => @ptDistanceSq(md.markerPt, footPt))
      marker = nearestMarkerDatum.marker
      markerCoords = marker.getLatLng()
      lastMarkerCoords = markerCoords
      leg = new L.Polyline [markerCoords, footLl], {
        color: @legColors.usual
        weight: @legWeight
        clickable: no
      }
      @map.addLayer(leg)
      marker._omsData = {usualPosition: marker.getLatLng(), leg: leg}
      unless @legColors.highlighted is @legColors.usual
        mhl = @makeHighlightListeners(marker)
        marker._omsData.highlightListeners = mhl
        marker.addEventListener('mouseover', mhl.highlight)
        marker.addEventListener('mouseout',  mhl.unhighlight)
      marker.setLatLng(footLl)
      if marker.hasOwnProperty('setZIndexOffset')
        marker.setZIndexOffset(1000000)
      marker
    delete @spiderfying
    @spiderfied = yes
    if @body && lastMarkerCoords != null
      body = L.circleMarker(lastMarkerCoords, @body)
      @map.addLayer(body)
      @bodies.push(body)
    @trigger('spiderfy', spiderfiedMarkers, nonNearbyMarkers)
  
  p.unspiderfy = (markerNotToMove = null) ->
    return @ unless @spiderfied?
    @unspiderfying = yes
    unspiderfiedMarkers = []
    nonNearbyMarkers = []
    for marker in @markers
      if marker._omsData?
        @map.removeLayer(marker._omsData.leg)
        marker.setLatLng(marker._omsData.usualPosition) unless marker is markerNotToMove
        if marker.hasOwnProperty('setZIndexOffset')
          marker.setZIndexOffset(0)
        mhl = marker._omsData.highlightListeners
        if mhl?
          marker.removeEventListener('mouseover', mhl.highlight)
          marker.removeEventListener('mouseout',  mhl.unhighlight)
        delete marker._omsData
        unspiderfiedMarkers.push(marker)
      else
        nonNearbyMarkers.push(marker)

    for body in @bodies
      @map.removeLayer(body)

    delete @unspiderfying
    delete @spiderfied
    @trigger('unspiderfy', unspiderfiedMarkers, nonNearbyMarkers)
    @  # return self, for chaining
  
  p.ptDistanceSq = (pt1, pt2) -> 
    dx = pt1.x - pt2.x
    dy = pt1.y - pt2.y
    dx * dx + dy * dy
  
  p.ptAverage = (pts) ->
    sumX = 0
    sumY = 0
    for pt in pts
      sumX += pt.x; sumY += pt.y
    numPts = pts.length
    new L.Point(sumX / numPts, sumY / numPts)
  
  p.minExtract = (set, func) ->  # destructive! returns minimum, and also removes it from the set
    for item, index in set
      val = func(item)
      if ! bestIndex? || val < bestVal
        bestVal = val
        bestIndex = index
    set.splice(bestIndex, 1)[0]
    
  p.arrIndexOf = (arr, obj) -> 
    return arr.indexOf(obj) if arr.indexOf?
    (return i if o is obj) for o, i in arr
    -1

extend = (out = {}) ->
  i = 1
  while i < arguments.length
    if !arguments[i]
      i++
      continue
    for key of arguments[i]
      if arguments[i].hasOwnProperty(key)
        out[key] = arguments[i][key]
    i++
  out