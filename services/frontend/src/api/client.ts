const BASE = import.meta.env.VITE_API_URL || ''

export interface Parcel {
  id: string
  tracking_code: string
  sender: string
  recipient_email: string
  destination_lat: number
  destination_lng: number
  status: string
  created_at: string
  events: ParcelEvent[]
}

export interface ParcelEvent {
  id: string
  status: string
  message: string
  timestamp: string
}

export interface Position {
  lat: number
  lng: number
  ts: string
  driver_id: string
}

export async function getParcel(id: string): Promise<Parcel> {
  const res = await fetch(`${BASE}/parcels/${id}`)
  if (!res.ok) throw new Error(`Parcel not found: ${id}`)
  return res.json()
}

export async function getPosition(id: string): Promise<Position | null> {
  const res = await fetch(`${BASE}/parcels/${id}/position`)
  if (res.status === 204) return null
  if (!res.ok) throw new Error('Position fetch failed')
  return res.json()
}
