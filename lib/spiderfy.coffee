'use strict'
###* @preserve Spiderfy
https://github.com/jawj/OverlappingMarkerSpiderfier-Leaflet
Copyright (c) 2011 - 2012 George MacKerron
Released under the MIT licence: http://opensource.org/licenses/mit-license
Note: The Leaflet maps API must be included *before* this code
###

# NB. string literal properties -- object.key -- are for Closure Compiler ADVANCED_OPTIMIZATION

return unless @L?  # return from wrapper func without doing anything

class @Spiderfy
  twoPi = Math.PI * 2

  # Note: it's OK that this constructor comes after the properties, because of function hoisting
  constructor: (@map, opts = {}) ->
    extend(@, opts, Spiderfy.defaultOpts)
    @enabled = yes
    @initMarkerArrays()
    @listeners = {}
    if @offEvents && @offEvents.length
      for e in @offEvents
        @map.addEventListener(e, @deactivate.bind(this))

  p = @::  # this saves a lot of repetition of .prototype that isn't optimized away
  p.VERSION = '1.0.0'
  p.initMarkerArrays = ->
    @markers = []
    @markerListeners = []
    @bodies = []

  p.addMarker = (marker) ->
    return @ if marker._hasSpiderfy?
    marker._hasSpiderfy = yes
    markerListener = () => @spiderListener(marker)
    if @onEvents && @onEvents.length
      for e in @onEvents
        marker.addEventListener(e, markerListener)
    @markerListeners.push(markerListener)
    @markers.push(marker)
    @  # return self, for chaining

  p.getMarkers = -> @markers[0..]  # returns a copy, so no funny business

  p.removeMarker = (marker) ->
    @deactivate() if marker._spiderfyData?  # otherwise it'll be stuck there forever!
    i = @arrIndexOf(@markers, marker)
    return @ if i < 0
    markerListener = @markerListeners.splice(i, 1)[0]
    if @onEvents && @onEvents.length
      for e in @onEvents
        marker.removeEventListener(e, markerListener)
    delete marker._hasSpiderfy
    @markers.splice(i, 1)
    @  # return self, for chaining

  p.clearMarkers = ->
    @deactivate()
    for marker, i in @markers
      markerListener = @markerListeners[i]
      if @onEvents && @onEvents.length
        for e in @onEvents
          marker.removeEventListener(e, markerListener)
      delete marker._hasSpiderfy
    @initMarkerArrays()
    @  # return self, for chaining

  # available listeners: click(marker), activate(markers), deactivate(markers)
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
    active = marker._spiderfyData?
    if !@keep
      @deactivate() unless active
    if active or !@enabled
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
        @activate(nearbyMarkerData, nonNearbyMarkers)
      else
        null

  p.makeHighlightListeners = (marker) ->
    highlight:   => marker._spiderfyData.leg.setStyle(color: @legColors.highlighted)
    unhighlight: => marker._spiderfyData.leg.setStyle(color: @legColors.usual)

  p.activate = (markerData, nonNearbyMarkers) ->
    return unless @enabled
    @activating = yes
    numFeet = markerData.length
    bodyPt = @ptAverage(md.markerPt for md in markerData)
    footPts = if numFeet >= @circleSpiralSwitchover
      @generatePtsSpiral(numFeet, bodyPt).reverse()  # match from outside in => less criss-crossing
    else
      @generatePtsCircle(numFeet, bodyPt)
    lastMarkerCoords = null
    activeMarkers = for footPt in footPts
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
      marker._spiderfyData = {usualPosition: marker.getLatLng(), leg: leg}
      unless @legColors.highlighted is @legColors.usual
        mhl = @makeHighlightListeners(marker)
        marker._spiderfyData.highlightListeners = mhl
        marker.addEventListener('mouseover', mhl.highlight)
        marker.addEventListener('mouseout',  mhl.unhighlight)
      marker.setLatLng(footLl)
      if marker.hasOwnProperty('setZIndexOffset')
        marker.setZIndexOffset(1000000)
      marker
    delete @activating
    @isActive = yes
    if @body && lastMarkerCoords != null
      body = L.circleMarker(lastMarkerCoords, @body)
      @map.addLayer(body)
      @bodies.push(body)
    @trigger('activate', activeMarkers, nonNearbyMarkers)

  p.deactivate = (markerNotToMove = null) ->
    return @ unless @isActive?
    @deactivating = yes
    inactiveMarkers = []
    nonNearbyMarkers = []
    for marker in @markers
      if marker._spiderfyData?
        @map.removeLayer(marker._spiderfyData.leg)
        marker.setLatLng(marker._spiderfyData.usualPosition) unless marker is markerNotToMove
        if marker.hasOwnProperty('setZIndexOffset')
          marker.setZIndexOffset(0)
        mhl = marker._spiderfyData.highlightListeners
        if mhl?
          marker.removeEventListener('mouseover', mhl.highlight)
          marker.removeEventListener('mouseout',  mhl.unhighlight)
        delete marker._spiderfyData
        inactiveMarkers.push(marker)
      else
        nonNearbyMarkers.push(marker)

    for body in @bodies
      @map.removeLayer(body)

    delete @deactivating
    delete @isActive
    @trigger('deactivate', inactiveMarkers, nonNearbyMarkers)
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
  p.enable = () ->
    @enabled = yes
    @
  p.disable = () ->
    @enabled = no
    @

@Spiderfy.defaultOpts =
  keep: no                     # yes -> don't deactivate when a marker is selected
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
  offEvents: ['click', 'zoomend']
  onEvents: ['click']
  body:
    color: '#222'
    radius: 3
    opacity: 0.9
    fillOpacity: 0.9
  msg:
    buttonEnabled: 'spiderfy enabled - click to disable'
    buttonDisabled: 'spiderfy disabled - click to enable'
  icon: '''
    <svg viewBox="-100 -100 200 200" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
       <g id="2">
         <g id="1">
           <circle cy="60" r="20"/>
           <path d="M 0,0 v 60" stroke="black" stroke-width="10"/>
         </g>
         <use xlink:href="#1" transform="scale(-1)"/>
       </g>
       <use xlink:href="#2" transform="rotate(60)"/>
      <use xlink:href="#2" transform="rotate(-60)"/>
    </svg>
'''

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

cleanExtend = (it, using) ->
  out = {}
  for key of using
    if using.hasOwnProperty(key)
      if it.hasOwnProperty(key)
        out[key] = it[key]
      else
        out[key] = value
  out

L.Spiderfy = L.Control.extend(
  options: extend(
      position: 'topleft'
      markers: []
      click: null
      activate: null
      deactivate: null
    Spiderfy.defaultOpts),
  onAdd: (map) ->
    _spiderfy = this._spiderfy = new Spiderfy(map, cleanExtend(@options, Spiderfy.defaultOpts))
    if @options.click
      _spiderfy.addListener('click', @options.click)
    if @options.activate
      _spiderfy.addListener('activate', @options.activate)
    if @options.deactivate
      _spiderfy.addListener('deactivate', @options.deactivate)
    active = yes
    buttonEnabled = @options.msg.buttonEnabled
    buttonDisabled = @options.msg.buttonDisabled
    button = L.DomUtil.create('a', 'leaflet-bar leaflet-control leaflet-control-spiderfy')
    button.setAttribute('href', '#')
    button.setAttribute('title', buttonEnabled)
    button.innerHTML = @options.icon
    style = button.style
    style.backgroundColor = 'white'
    style.width = '30px'
    style.height = '30px'
    for marker in @options.markers
      _spiderfy.addMarker(marker)
    button.onclick = () ->
      if (active)
        active = no
        button.setAttribute('title', buttonDisabled)
        style.opacity = 0.5
        _spiderfy
          .deactivate()
          .disable()
      else
        active = yes
        button.setAttribute('title', buttonEnabled)
        style.opacity = 1
        _spiderfy
          .enable()
    button
  # expose methods from Spiderfy class
  VERSION = Spiderfy.prototype.VERSION
  initMarkerArrays = ->
    @_spiderfy.initMarkerArrays()
    @
  addMarker = (marker) ->
    @_spiderfy.addMarker(marker)
    @
  getMarkers = ->
    @_spiderfy.getMarkers()
  removeMarker = (marker) ->
    @_spiderfy.removeMarker(marker)
    @
  clearMarkers = ->
    @_spiderfy.clearMarkers()
    @
  addListener = (event, func) ->
    @_spiderfy.addListener(event, func)
    @
  removeListener = (event, func) ->
    @_spiderfy.removeListener(event, func)
    @
  clearListeners = (event) ->
    @_spiderfy.clearListeners(event)
    @
  trigger = (event, args...) ->
    @_spiderfy.trigger(event, args)
    @
  generatePtsCircle = (count, centerPt) ->
    @_spiderfy.generatePtsCircle(count, centerPt)
    @
  generatePtsSpiral = (count, centerPt) ->
    @_spiderfy.generatePtsSpiral(count, centerPt)
  spiderListener = (marker) ->
    @_spiderfy.spiderListener(marker)
    @
  makeHighlightListeners = (marker) ->
    @_spiderfy.makeHighlightListeners(marker)
    @
  activate = (markerData, nonNearbyMarkers) ->
    @_spiderfy(markerData, nonNearbyMarkers)
    @
  deactivate = (markerNotToMove = null) ->
    @_spiderfy.deactivate(markerNotToMove)
    @
  ptDistanceSq = (pt1, pt2) ->
    @_spiderfy.ptDistanceSq(pt1, pt2)
  ptAverage = (pts) ->
    @_spiderfy.ptAverage(pts)
  minExtract = (set, func) ->
    @_spiderfy.minExtract(set, func)
  arrIndexOf = (arr, obj) ->
    @_spiderfy.arrIndexOf(arr, obj);
  enable = ->
    @_spiderfy.enable()
    @
  disable = ->
    @_spiderfy.disable()
    @
)

L.spiderfy = (options) ->
  spiderfy = new L.Spiderfy(options)
  map.addControl(spiderfy)
  spiderfy