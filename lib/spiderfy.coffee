'use strict'
###* @preserve Spiderfy
https://github.com/jawj/OverlappingMarkerSpiderfier-Leaflet
Copyright (c) 2011 - 2016 George MacKerron
Released under the MIT licence: http://opensource.org/licenses/mit-license
Note: The Leaflet maps API must be included *before* this code
###

# NB. string literal properties -- object.key -- are for Closure Compiler ADVANCED_OPTIMIZATION

return if @.hasOwnProperty('L') is no # return from wrapper func without doing anything

class @Spiderfy
  twoPi = Math.PI * 2

  # Note: it's OK that this constructor comes after the properties, because of function hoisting
  constructor: (@map, opts = {}) ->
    for key of Spiderfy.defaults
      continue if Spiderfy.defaults.hasOwnProperty(key) is no
      @[key] = if opts.hasOwnProperty(key) then opts[key] else Spiderfy.defaults[key]
    @isEnabled = yes
    @initMarkerArrays()
    @listeners = {}
    @bounds = null
    @ne = null
    @sw = null
    @visibleMarkers = []
    @isActivating = no
    @isDeactivating = no
    @data = {}
    if @viewportOnly
      @updateBounds()
      @map.on('moveend', @updateBounds.bind(@))
    if @offEvents and @offEvents.length
      for e in @offEvents
        @map.on(e, @deactivate.bind(@))

  @::=

  VERSION: '1.0.0'
  initMarkerArrays: () ->
    @markers = []
    @markerListeners = []
    @bodies = []

  addMarker: (marker) ->
    return @ if @data.hasOwnProperty(marker._leaflet_id)
    markerListener = () => @activateMarker(marker)
    if @onEvents.constructor is Array and @onEvents.length > 0
      for e in @onEvents
        marker.on(e, markerListener)
    @markerListeners.push(markerListener)
    @markers.push(marker)
    @

  getMarkers: () -> @markers[0..]  # returns a copy, so no funny business

  removeMarker: (marker) ->
    @deactivate() if @data.hasOwnProperty(marker._leaflet_id)  # otherwise it'll be stuck there forever!
    i = @arrIndexOf(@markers, marker)
    return @ if i < 0
    markerListener = @markerListeners.splice(i, 1)[0]
    if @onEvents and @onEvents.length
      for e in @onEvents
        marker.removeEventListener(e, markerListener)
    delete @data[marker._leaflet_id]
    @markers.splice(i, 1)
    @

  clearMarkers: () ->
    @deactivate()
    for marker, i in @markers
      markerListener = @markerListeners[i]
      if @onEvents and @onEvents.length > 0
        for e in @onEvents
          marker.removeEventListener(e, markerListener)
      delete @data[marker._leaflet_id]
    @initMarkerArrays()
    @

  # available listeners: click(marker), activate(markers), deactivate(markers)
  addListener: (event, func) ->
    (@listeners[event] ?= []).push(func)
    @

  removeListener: (event, func) ->
    i = @arrIndexOf(@listeners[event], func)
    @listeners[event].splice(i, 1) unless i < 0
    @

  clearListeners: (event) ->
    @listeners[event] = []
    @

  trigger: (event, args...) ->
    func(args...) for func in (@listeners[event] ? [])

  generatePtsCircle: (count, centerPt) ->
    circumference = @circleFootSeparation * (2 + count)
    legLength = if count > 6 then circumference / twoPi else @circleFootSeparation  # = radius from circumference
    angleStep = twoPi / count
    calculatedStartAngle = @circleStartAngle * (Math.PI / 180)
    for i in [0...count]
      angle = calculatedStartAngle + i * angleStep
      new L.Point(centerPt.x + legLength * Math.cos(angle),
                  centerPt.y + legLength * Math.sin(angle))

  generatePtsSpiral: (count, centerPt) ->
    legLength = @spiralLengthStart
    angle = 0
    for i in [0...count]
      angle += @spiralFootSeparation / legLength + i * 0.0005
      pt = new L.Point(centerPt.x + legLength * Math.cos(angle),
                       centerPt.y + legLength * Math.sin(angle))
      legLength += twoPi * @spiralLengthFactor / angle
      pt

  activateMarker: (marker) ->
    isActive = @data.hasOwnProperty(marker._leaflet_id)
    if @keep is no
      @deactivate() unless isActive
    latLng = marker.getLatLng()
    return @ if @viewportOnly and @isInViewPort(latLng) is no

    if isActive or @isEnabled is no
      @trigger('click', marker)
    else
      nearbyMarkerData = []
      nonNearbyMarkers = []
      pxSq = @nearbyDistance * @nearbyDistance
      markerPt = @map.latLngToLayerPoint(latLng)
      for m in @markers
        continue unless @map.hasLayer(m)
        mPt = @map.latLngToLayerPoint(m.getLatLng())
        if @ptDistanceSq(mPt, markerPt) < pxSq
          nearbyMarkerData.push(marker: m, markerPt: mPt)
        else
          nonNearbyMarkers.push(m)
      if nearbyMarkerData.length is 1  # 1 => the one clicked => none nearby
        @trigger('click', marker)
      else if nearbyMarkerData.length > 0 and nonNearbyMarkers.length > 0
        @activate(nearbyMarkerData, nonNearbyMarkers)
    @

  setColorStyle: (item, color) ->
    item.setStyle(color: color)

  activate: (markerData, nonNearbyMarkers) ->
    return @ unless @isEnabled
    return @ if @isActivating
    @isActivating = yes
    @updateBounds() if @viewportOnly is yes
    numFeet = markerData.length
    bodyPt = @ptAverage(md.markerPt for md in markerData)
    footPts = if numFeet >= @circleSpiralSwitchover
      @generatePtsSpiral(numFeet, bodyPt).reverse()  # match from outside in => less criss-crossing
    else
      @generatePtsCircle(numFeet, bodyPt)
    lastMarkerCoords = null
    activeMarkers = []
    for footPt in footPts
      footLl = @map.layerPointToLatLng(footPt)
      nearestMarkerDatum = @minExtract(markerData, (md) => @ptDistanceSq(md.markerPt, footPt))
      marker = nearestMarkerDatum.marker
      markerCoords = marker.getLatLng()
      lastMarkerCoords = markerCoords
      leg = new L.Polyline([markerCoords, footLl],
        color: @legColors.usual
        weight: @legWeight
        clickable: no)

      @map.addLayer(leg)
      if @data.hasOwnProperty(marker._leaflet_id)
        oldData = @data[marker._leaflet_id]
        @map.removeLayer(oldData.leg)
      data = @data[marker._leaflet_id] =
        usualPosition: marker.getLatLng()
        leg: leg
      unless @legColors.highlighted is @legColors.usual
        marker.on('mouseover', data.over = @setColorStyle.bind(@, data.leg, @legColors.highlighted))
        marker.on('mouseout', data.out = @setColorStyle.bind(@, data.leg, @legColors.usual))
      marker.setLatLng(footLl)
      if marker.hasOwnProperty('setZIndexOffset')
        marker.setZIndexOffset(1000000)
      @visibleMarkers.push(marker)
      activeMarkers.push(marker)
    @isActivating = no
    @isActive = yes
    if @body and lastMarkerCoords
      body = L.circleMarker(lastMarkerCoords, @body)
      @map.addLayer(body)
      @bodies.push(body)
      @data[marker._leaflet_id].body = body
    @trigger('activate', activeMarkers, nonNearbyMarkers)

  deactivate: (markerNotToMove = null) ->
    return @ if @isActive is no
    return @ if @isDeactivating
    @isDeactivating = yes
    inactiveMarkers = []
    nonNearbyMarkers = []
    for marker in @visibleMarkers
      if @data.hasOwnProperty(marker._leaflet_id)
        data = @data[marker._leaflet_id]
        delete @data[marker._leaflet_id]
        @map.removeLayer(data.leg)
        marker.setLatLng(data.usualPosition) unless marker is markerNotToMove
        if marker.hasOwnProperty('setZIndexOffset')
          marker.setZIndexOffset(0)
        if data.hasOwnProperty('over')
          marker.off('mouseover', data.over)
          marker.off('mouseout', data.out)
        inactiveMarkers.push(marker)
        activeMarkerIndex = @visibleMarkers.indexOf(marker)
        if activeMarkerIndex > -1 then @visibleMarkers.splice(activeMarkerIndex, -1)
      else
        nonNearbyMarkers.push(marker)

    for body in @bodies
      @map.removeLayer(body)

    @isDeactivating = no
    @isActive = no
    @trigger('deactivate', inactiveMarkers, nonNearbyMarkers)
    @

  ptDistanceSq: (pt1, pt2) ->
    dx = pt1.x - pt2.x
    dy = pt1.y - pt2.y
    dx * dx + dy * dy

  ptAverage: (pts) ->
    sumX = 0
    sumY = 0
    for pt in pts
      sumX += pt.x
      sumY += pt.y
    numPts = pts.length
    new L.Point(sumX / numPts, sumY / numPts)

  minExtract: (array, func) ->  # destructive! returns minimum, and also removes it from the array
    for item, index in array
      val = func(item)
      if ! bestIndex? || val < bestVal
        bestVal = val
        bestIndex = index
    array.splice(bestIndex, 1)[0]

  arrIndexOf: (array, obj) ->
    return array.indexOf(obj) if array.constructor is Array
    (return i if o is obj) for o, i in array
    -1
  enable: () ->
    @isEnabled = yes
    @
  disable: () ->
    @isEnabled = no
    @
  updateBounds: () ->
    bounds = @bounds = @map.getBounds()
    @ne = bounds._northEast
    @sw = bounds._southWest
    @

  isInViewPort: (latLng) ->
    latLng.lat > @sw.lat and
    latLng.lat < @ne.lat and
    latLng.lng > @sw.lng and
    latLng.lng < @ne.lng


defaults = @Spiderfy.defaults =
  keep: no                     # yes -> don't deactivate when a marker is selected
  viewportOnly: yes
  nearbyDistance: 20           # spiderfy markers within this range of the one clicked, in px

  circleSpiralSwitchover: 9    # show spiral instead of circle from this marker count upwards
  # 0 -> always spiral: Infinity -> always circle
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

L.Spiderfy = L.Control.extend(
  options:
    position: 'topleft'
    markers: []
    click: null
    activate: null
    deactivate: null
    enable: null
    disable: null
    keep: defaults.keep
    nearbyDistance: defaults.nearbyDistance
    circleSpiralSwitchover: defaults.circleSpiralSwitchover
    circleFootSeparation: defaults.circleFootSeparation
    circleStartAngle: defaults.circleStartAngle
    spiralFootSeparation: defaults.spiralFootSeparation
    spiralLengthStart: defaults.spiralLengthStart
    spiralLengthFactor: defaults.spiralLengthFactor
    legWeight: defaults.legWeight
    legColors: defaults.legColors
    offEvents: defaults.offEvents
    onEvents: defaults.onEvents
    body: defaults.body
    msg: defaults.msg
    icon: defaults.icon
  onAdd: (map) ->
    options = @options
    _spiderfy = @_spiderfy = new Spiderfy(map, options)
    if options.click then _spiderfy.addListener('click', options.click)
    if options.activate then _spiderfy.addListener('activate', options.activate)
    if options.deactivate then _spiderfy.addListener('deactivate', options.deactivate)
    isActive = yes
    buttonEnabled = options.msg.buttonEnabled
    buttonDisabled = options.msg.buttonDisabled
    button = L.DomUtil.create('a', 'leaflet-bar leaflet-control leaflet-control-spiderfy')
    button.setAttribute('href', '#')
    button.setAttribute('title', buttonEnabled)
    button.innerHTML = options.icon
    style = button.style
    style.backgroundColor = 'white'
    style.width = '30px'
    style.height = '30px'
    for marker in options.markers
      _spiderfy.addMarker(marker)

    button.onclick = () ->
      if (isActive)
        isActive = no
        button.setAttribute('title', buttonDisabled)
        style.opacity = 0.5
        _spiderfy
          .deactivate()
          .disable()

        if options.disable
          options.disable()
      else
        isActive = yes
        button.setAttribute('title', buttonEnabled)
        style.opacity = 1
        _spiderfy
          .enable()

        if options.enable
          options.enable()
    button

  # expose methods from Spiderfy class
  VERSION: Spiderfy.prototype.VERSION
  initMarkerArrays: () ->
    @_spiderfy.initMarkerArrays()
    @
  addMarker: (marker) ->
    @_spiderfy.addMarker(marker)
    @
  getMarkers: () ->
    @_spiderfy.getMarkers()
  removeMarker: (marker) ->
    @_spiderfy.removeMarker(marker)
    @
  clearMarkers: () ->
    @_spiderfy.clearMarkers()
    @
  addListener: (event, func) ->
    @_spiderfy.addListener(event, func)
    @
  removeListener: (event, func) ->
    @_spiderfy.removeListener(event, func)
    @
  clearListeners: (event) ->
    @_spiderfy.clearListeners(event)
    @
  trigger: (event, args...) ->
    @_spiderfy.trigger(event, args)
    @
  generatePtsCircle: (count, centerPt) ->
    @_spiderfy.generatePtsCircle(count, centerPt)
    @
  generatePtsSpiral: (count, centerPt) ->
    @_spiderfy.generatePtsSpiral(count, centerPt)
  activateMarker: (marker) ->
    @_spiderfy.activateMarker(marker)
    @
  activate: (markerData, nonNearbyMarkers) ->
    @_spiderfy.activate(markerData, nonNearbyMarkers)
    @
  deactivate: (markerNotToMove) ->
    @_spiderfy.deactivate(markerNotToMove)
    @
  hideVisibleMarkers: () ->
    @_spiderfy.hideVisibleMarkers()
    @
  ptDistanceSq: (pt1, pt2) ->
    @_spiderfy.ptDistanceSq(pt1, pt2)
  ptAverage: (pts) ->
    @_spiderfy.ptAverage(pts)
  minExtract: (array, func) ->
    @_spiderfy.minExtract(array, func)
  arrIndexOf: (arr, obj) ->
    @_spiderfy.arrIndexOf(arr, obj)
  enable: () ->
    @_spiderfy.enable()
    @
  disable: () ->
    @_spiderfy.disable()
    @
  updateBounds: () ->
    @_spiderfy.updateBounds()
    @
  isInViewPort: (latLng) ->
    @_spiderfy.isInViewPort(latLng)
)

L.spiderfy = (options) ->
  spiderfy = new L.Spiderfy(options)
  map.addControl(spiderfy)
  spiderfy
