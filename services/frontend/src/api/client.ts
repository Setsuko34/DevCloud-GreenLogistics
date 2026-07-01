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

export async function getParcel(trackingCode: string): Promise<Parcel> {
  const res = await fetch(`${BASE}/parcels/${trackingCode}`)
  if (!res.ok) throw new Error(`Parcel not found: ${trackingCode}`)
  return res.json()
}

export async function getPosition(trackingCode: string): Promise<Position | null> {
  const res = await fetch(`${BASE}/parcels/${trackingCode}/position`)
  if (res.status === 204) return null
  if (!res.ok) throw new Error('Position fetch failed')
  return res.json()
}
