// services/api/tests/parcels.test.ts
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

describe('POST /parcels', () => {
  it('returns 201 with a tracking_code', async () => {
    const res = await app.inject({ method: 'POST', url: '/parcels', payload })
    expect(res.statusCode).toBe(201)
    const body = JSON.parse(res.body)
    expect(body).toHaveProperty('id')
    expect(body).toHaveProperty('tracking_code')
    expect(body.status).toBe('CREATED')
  })
})

describe('GET /parcels/:id', () => {
  it('returns 200 with parcel and events', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', payload })
    const { id, tracking_code } = JSON.parse(create.body)
    const res = await app.inject({ method: 'GET', url: `/parcels/${tracking_code}` })
    expect(res.statusCode).toBe(200)
    const body = JSON.parse(res.body)
    expect(body.id).toBe(id)
    expect(Array.isArray(body.events)).toBe(true)
  })

  it('returns 404 for unknown id', async () => {
    const res = await app.inject({ method: 'GET', url: '/parcels/00000000-0000-0000-0000-000000000000' })
    expect(res.statusCode).toBe(404)
  })
})

describe('PATCH /parcels/:id/status', () => {
  it('updates status and adds event', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', payload })
    const { id } = JSON.parse(create.body)
    const res = await app.inject({
      method: 'PATCH',
      url: `/parcels/${id}/status`,
      payload: { status: 'IN_TRANSIT' }
    })
    expect(res.statusCode).toBe(200)
    expect(JSON.parse(res.body).status).toBe('IN_TRANSIT')
  })
})

describe('GET /parcels/:id/position', () => {
  it('returns 204 when no GPS position available', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', payload })
    const { tracking_code } = JSON.parse(create.body)
    const res = await app.inject({ method: 'GET', url: `/parcels/${tracking_code}/position` })
    expect(res.statusCode).toBe(204)
  })
})
