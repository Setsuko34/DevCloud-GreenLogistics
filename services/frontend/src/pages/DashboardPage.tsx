import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { listParcels, ParcelWithPosition } from '../api/client'
import { useLivePositions } from '../hooks/useLivePositions'
import { ParcelMap } from '../components/ParcelMap'
import { StatusBadge } from '../components/StatusBadge'

export function DashboardPage() {
  const [parcels, setParcels] = useState<ParcelWithPosition[]>([])
  const livePositions = useLivePositions()

  useEffect(() => {
    const refresh = async () => {
      try {
        setParcels(await listParcels())
      } catch {
        // API temporairement indisponible — on garde le dernier état affiché
      }
    }
    refresh()
    const interval = setInterval(refresh, 10000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="page">
      <h1>Tous les colis</h1>
      {parcels.length === 0 && <p>Aucun colis pour le moment.</p>}
      <div className="dashboard-grid">
        {parcels.map((p) => (
          <div key={p.id} className="card">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
              <h3 style={{ margin: 0 }}>
                <Link to={`/?code=${p.tracking_code}`}>{p.tracking_code}</Link>
              </h3>
              <StatusBadge status={p.status} />
            </div>
            <ParcelMap
              position={livePositions[p.id] ?? p.position}
              destination={{ lat: p.destination_lat, lng: p.destination_lng }}
            />
          </div>
        ))}
      </div>
    </div>
  )
}
