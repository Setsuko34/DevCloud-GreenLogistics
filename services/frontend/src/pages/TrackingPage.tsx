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
    <div style={{ padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1>Suivi de colis</h1>
      <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="ID ou code de suivi"
          style={{ flex: 1, padding: '0.5rem' }}
        />
        <button onClick={() => setParcelId(input)} style={{ padding: '0.5rem 1rem' }}>
          Suivre
        </button>
      </div>

      {error && <p style={{ color: 'red' }}>{error}</p>}

      {parcel && (
        <div>
          <p><strong>Code :</strong> {parcel.tracking_code}</p>
          <p><strong>Statut :</strong> <StatusBadge status={parcel.status} /></p>
          <p><strong>Destinataire :</strong> {parcel.recipient_email}</p>

          <ParcelMap
            position={position}
            destination={{ lat: parcel.destination_lat, lng: parcel.destination_lng }}
          />

          <h3>Historique</h3>
          <ul>
            {parcel.events.map((e) => (
              <li key={e.id}>
                <StatusBadge status={e.status} /> {e.message} — {new Date(e.timestamp).toLocaleString()}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
