import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useEffect, useRef } from 'react'
import type { Coordinate } from '../core/types'
import { TILE_ATTRIBUTION, TILE_MAX_ZOOM, TILE_URL } from '../services/tiles'
import { ACCENT } from '../theme'

export interface MapPin {
  /** 머문 곳 id. */
  id: string
  number: number
  title: string
  coordinate: Coordinate
}

interface Props {
  pins: MapPin[]
  /** 날짜별 경로. */
  routes: Coordinate[][]
  /** 지도를 옮길 곳. 같은 곳을 다시 눌러도 옮겨지도록 매번 새 값을 준다. */
  focus: { coordinate: Coordinate } | null
}

const latLng = (c: Coordinate): L.LatLngTuple => [c.latitude, c.longitude]
const escapeHTML = (text: string) => text.replace(/[&<>"]/g, (char) => `&#${char.charCodeAt(0)};`)

/** 머문 곳 번호 핀과 날짜별 경로 선. */
export function TimelineMap({ pins, routes, focus }: Props) {
  const container = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const routeLayer = useRef<L.LayerGroup | null>(null)
  /** 머문 곳 id → 지도에 올린 핀. 이름만 바뀌면 핀을 새로 만들지 않고 글자만 고친다. */
  const markers = useRef(new Map<string, { marker: L.Marker; pin: MapPin }>())
  /** 지금 지도 범위를 맞춘 머문 곳들. 이름만 바뀌었을 때는 범위를 다시 맞추지 않는다. */
  const fitted = useRef('')
  /** 창 크기가 바뀔 때 다시 맞출 범위. 사용자가 지도를 직접 움직이면 비운다. */
  const bounds = useRef<L.LatLngBounds | null>(null)

  useEffect(() => {
    const element = container.current!
    const created = L.map(element, { scrollWheelZoom: false }).setView([36.5, 127.8], 6)
    L.tileLayer(TILE_URL, { maxZoom: TILE_MAX_ZOOM, attribution: TILE_ATTRIBUTION }).addTo(created)
    routeLayer.current = L.layerGroup().addTo(created)
    map.current = created
    const pinMarkers = markers.current
    // 창 크기가 바뀌면 지도 크기를 다시 재고, 핀이 모두 보이게 범위를 다시 맞춘다.
    const observer = new ResizeObserver(() => {
      created.invalidateSize()
      if (bounds.current) {
        created.fitBounds(bounds.current, { padding: [40, 40], maxZoom: 16, animate: false })
      }
    })
    observer.observe(element)
    // 사용자가 지도를 직접 움직이거나 확대하면, 그 뒤로는 범위를 되돌리지 않는다.
    const touched = () => {
      bounds.current = null
    }
    element.addEventListener('pointerdown', touched)
    return () => {
      element.removeEventListener('pointerdown', touched)
      observer.disconnect()
      created.remove()
      map.current = null
      routeLayer.current = null
      pinMarkers.clear()
      fitted.current = ''
      bounds.current = null
    }
  }, [])

  // 날짜별로 선을 따로 그려, 다른 날의 장소끼리 이어지지 않게 한다.
  useEffect(() => {
    if (!routeLayer.current) return
    routeLayer.current.clearLayers()
    for (const route of routes) {
      if (route.length > 1) {
        L.polyline(route.map(latLng), { color: ACCENT, weight: 4, opacity: 0.85 }).addTo(routeLayer.current)
      }
    }
  }, [routes])

  useEffect(() => {
    if (!map.current) return
    const wanted = new Set(pins.map((pin) => pin.id))
    for (const [id, { marker }] of markers.current) {
      if (!wanted.has(id)) {
        marker.remove()
        markers.current.delete(id)
      }
    }
    for (const pin of pins) {
      const existing = markers.current.get(pin.id)
      const same =
        existing &&
        existing.pin.number === pin.number &&
        existing.pin.coordinate.latitude === pin.coordinate.latitude &&
        existing.pin.coordinate.longitude === pin.coordinate.longitude
      if (existing && same) {
        // 이름이 늦게 도착했을 때: 핀은 그대로 두고 글자만 바꾼다(열려 있는 말풍선이 닫히지 않는다).
        if (existing.pin.title !== pin.title) {
          existing.marker.getElement()?.setAttribute('title', pin.title)
          existing.marker.setTooltipContent(escapeHTML(pin.title))
          existing.pin = pin
        }
        continue
      }
      existing?.marker.remove()
      const marker = L.marker(latLng(pin.coordinate), {
        icon: L.divIcon({ className: 'map-pin', html: `<span>${pin.number}</span>`, iconSize: [30, 30], iconAnchor: [15, 15] }),
        title: pin.title,
      })
        .bindTooltip(escapeHTML(pin.title))
        .addTo(map.current)
      markers.current.set(pin.id, { marker, pin })
    }
    const key = pins.map((pin) => pin.id).join('\n')
    if (pins.length > 0 && key !== fitted.current) {
      fitted.current = key
      bounds.current = L.latLngBounds(pins.map((pin) => latLng(pin.coordinate)))
      map.current.fitBounds(bounds.current, { padding: [40, 40], maxZoom: 16 })
    }
  }, [pins])

  useEffect(() => {
    if (focus && map.current) {
      // 한 곳을 골라 보는 동안에는 창 크기가 바뀌어도 전체 범위로 돌아가지 않는다.
      bounds.current = null
      map.current.setView(latLng(focus.coordinate), 16, { animate: true })
    }
  }, [focus])

  return <div ref={container} className="map" data-testid="map" />
}
