import { useState, useEffect } from 'react'
import { getParcel, getPosition, Position } from '../api/client'
import { ParcelMap } from '../components/ParcelMap'
import { StatusBadge } from '../components/StatusBadge'

const DEMO_IDS = ['PARCEL-DEMO-001', 'PARCEL-DEMO-002']

export function DashboardPage() {
  const [positions, setPositions] = useState<Record<string, Position | null>>({})
  const [statuses, setStatuses] = useState<Record<string, string>>({})

  useEffect(() => {
    const refresh = async () => {
      const results = await Promise.allSettled(
        DEMO_IDS.map(async (id) => {
          const [parcel, pos] = await Promise.all([getParcel(id), getPosition(id)])
          return { id, parcel, pos }
        })
      )
      const newPos: Record<string, Position | null> = {}
      const newStatus: Record<string, string> = {}
      results.forEach((r) => {
        if (r.status === 'fulfilled') {
          newPos[r.value.id] = r.value.pos
          newStatus[r.value.id] = r.value.parcel.status
        }
      })
      setPositions(newPos)
      setStatuses(newStatus)
    }
    refresh()
    const interval = setInterval(refresh, 5000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div style={{ padding: '2rem' }}>
      <h1>Dashboard démo — Livreurs actifs</h1>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '2rem' }}>
        {DEMO_IDS.map((id) => (
          <div key={id} style={{ border: '1px solid #eee', borderRadius: '8px', padding: '1rem' }}>
            <h3>Colis {id}</h3>
            <StatusBadge status={statuses[id] ?? 'UNKNOWN'} />
            <ParcelMap
              position={positions[id] ?? null}
              destination={{ lat: 48.8566, lng: 2.3522 }}
            />
          </div>
        ))}
      </div>
    </div>
  )
}
