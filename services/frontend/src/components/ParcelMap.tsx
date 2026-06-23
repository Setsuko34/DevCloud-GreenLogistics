import { useEffect, useRef } from 'react'
import L from 'leaflet'
import type { Position } from '../api/client'

interface Props {
  position: Position | null
  destination: { lat: number; lng: number }
}

export function ParcelMap({ position, destination }: Props) {
  const mapRef = useRef<L.Map | null>(null)
  const markerRef = useRef<L.Marker | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return
    mapRef.current = L.map(containerRef.current).setView(
      [destination.lat, destination.lng], 13
    )
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(mapRef.current)
    L.marker([destination.lat, destination.lng])
      .addTo(mapRef.current)
      .bindPopup('Destination')
  }, [destination])

  useEffect(() => {
    if (!mapRef.current || !position) return
    const latlng: L.LatLngExpression = [position.lat, position.lng]
    if (markerRef.current) {
      markerRef.current.setLatLng(latlng)
    } else {
      markerRef.current = L.marker(latlng)
        .addTo(mapRef.current!)
        .bindPopup('Livreur')
    }
    mapRef.current.panTo(latlng)
  }, [position])

  return <div ref={containerRef} style={{ height: '400px', width: '100%' }} />
}
