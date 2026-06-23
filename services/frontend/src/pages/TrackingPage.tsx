import { useState, useEffect, useCallback } from 'react'
import { getParcel, getPosition, Parcel, Position } from '../api/client'
import { ParcelMap } from '../components/ParcelMap'
import { StatusBadge } from '../components/StatusBadge'

export function TrackingPage() {
  const [input, setInput] = useState('')
  const [parcelId, setParcelId] = useState<string | null>(null)
  const [parcel, setParcel] = useState<Parcel | null>(null)
  const [position, setPosition] = useState<Position | null>(null)
  const [error, setError] = useState<string | null>(null)

  const fetchParcel = useCallback(async (id: string) => {
    try {
      const p = await getParcel(id)
      setParcel(p)
      setError(null)
    } catch {
      setError('Colis introuvable')
    }
  }, [])

  const fetchPosition = useCallback(async (id: string) => {
    const pos = await getPosition(id)
    setPosition(pos)
  }, [])

  useEffect(() => {
    if (!parcelId) return
    fetchParcel(parcelId)
    fetchPosition(parcelId)
    const interval = setInterval(() => fetchPosition(parcelId), 5000)
    return () => clearInterval(interval)
  }, [parcelId, fetchParcel, fetchPosition])

  return (
    <div className="page">
      <h1>Suivi de colis</h1>

      <div className="search-row">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && setParcelId(input)}
          placeholder="ID ou code de suivi"
        />
        <button onClick={() => setParcelId(input)}>Suivre</button>
      </div>

      {error && <p className="error">{error}</p>}

      {parcel && (
        <div className="card">
          <div className="parcel-meta">
            <p><strong>Code :</strong> {parcel.tracking_code}</p>
            <p><strong>Statut :</strong> <StatusBadge status={parcel.status} /></p>
            <p><strong>Destinataire :</strong> {parcel.recipient_email}</p>
          </div>

          <ParcelMap
            position={position}
            destination={{ lat: parcel.destination_lat, lng: parcel.destination_lng }}
          />

          <div className="history" style={{ marginTop: '1.5rem' }}>
            <h3>Historique</h3>
            <ul className="history-list">
              {parcel.events.map((e) => (
                <li key={e.id}>
                  <StatusBadge status={e.status} />
                  <span>{e.message} — {new Date(e.timestamp).toLocaleString()}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  )
}
