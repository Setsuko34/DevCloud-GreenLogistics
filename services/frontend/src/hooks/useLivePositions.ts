import { useEffect, useState } from 'react'
import type { Position } from '../api/client'

type LivePosition = Position & { parcel_id: string }

export function useLivePositions(): Record<string, Position> {
  const [positions, setPositions] = useState<Record<string, Position>>({})

  useEffect(() => {
    const wsBase = `${window.location.origin.replace(/^http/, 'ws')}/ws/positions`
    const socket = new WebSocket(wsBase)

    socket.onmessage = (event) => {
      const pos: LivePosition = JSON.parse(event.data)
      setPositions((prev) => ({
        ...prev,
        [pos.parcel_id]: { lat: pos.lat, lng: pos.lng, ts: pos.ts, driver_id: pos.driver_id }
      }))
    }

    return () => socket.close()
  }, [])

  return positions
}
