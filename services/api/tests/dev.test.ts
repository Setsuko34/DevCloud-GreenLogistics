// services/api/tests/dev.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { build } from '../src/app'
import { FastifyInstance } from 'fastify'

let app: FastifyInstance

beforeAll(async () => { app = await build({ testing: true }) })
afterAll(async () => { await app.close() })

const payload = {
  sender: 'Alice',
  recipient_email: 'bob@example.com',
  destination_lat: 48.8566,
  destination_lng: 2.3522
}

async function createParcel() {
  const res = await app.inject({ method: 'POST', url: '/parcels', payload })
  return JSON.parse(res.body) as { id: string; tracking_code: string }
}

describe('POST /dev/seed-position', () => {
  it('flips status to IN_TRANSIT on the first position update, far from destination', async () => {
    const { id, tracking_code } = await createParcel()

    const res = await app.inject({
      method: 'POST',
      url: '/dev/seed-position',
      payload: { parcel_id: id, lat: 49.0, lng: 2.0 }
    })
    expect(res.statusCode).toBe(201)

    const parcel = JSON.parse((await app.inject({ method: 'GET', url: `/parcels/${tracking_code}` })).body)
    expect(parcel.status).toBe('IN_TRANSIT')
  })

  it('flips status to DELIVERED once the position matches the destination', async () => {
    const { id, tracking_code } = await createParcel()

    await app.inject({
      method: 'POST',
      url: '/dev/seed-position',
      payload: { parcel_id: id, lat: payload.destination_lat, lng: payload.destination_lng }
    })

    const parcel = JSON.parse((await app.inject({ method: 'GET', url: `/parcels/${tracking_code}` })).body)
    expect(parcel.status).toBe('DELIVERED')
  })
})
