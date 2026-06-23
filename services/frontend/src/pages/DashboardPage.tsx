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
    <div className="page">
      <h1>Livreurs actifs</h1>
      <div className="dashboard-grid">
        {DEMO_IDS.map((id) => (
          <div key={id} className="card">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
              <h3 style={{ margin: 0 }}>{id}</h3>
              <StatusBadge status={statuses[id] ?? 'UNKNOWN'} />
            </div>
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
