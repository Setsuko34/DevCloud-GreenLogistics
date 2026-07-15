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

const authHeaders = { 'x-api-key': 'test-key' }

describe('POST /parcels', () => {
  it('returns 201 with a tracking_code', async () => {
    const res = await app.inject({ method: 'POST', url: '/parcels', headers: authHeaders, payload })
    expect(res.statusCode).toBe(201)
    const body = JSON.parse(res.body)
    expect(body).toHaveProperty('id')
    expect(body).toHaveProperty('tracking_code')
    expect(body.status).toBe('CREATED')
  })

  it('returns 401 without a valid API key', async () => {
    const res = await app.inject({ method: 'POST', url: '/parcels', payload })
    expect(res.statusCode).toBe(401)
  })

  it('returns 400 for an invalid payload', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/parcels',
      headers: authHeaders,
      payload: { ...payload, recipient_email: 'not-an-email' }
    })
    expect(res.statusCode).toBe(400)
  })
})

describe('GET /parcels/:id', () => {
  it('returns 200 with parcel and events', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', headers: authHeaders, payload })
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
    const create = await app.inject({ method: 'POST', url: '/parcels', headers: authHeaders, payload })
    const { id } = JSON.parse(create.body)
    const res = await app.inject({
      method: 'PATCH',
      url: `/parcels/${id}/status`,
      headers: authHeaders,
      payload: { status: 'IN_TRANSIT' }
    })
    expect(res.statusCode).toBe(200)
    expect(JSON.parse(res.body).status).toBe('IN_TRANSIT')
  })

  it('returns 400 for an unknown status value', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', headers: authHeaders, payload })
    const { id } = JSON.parse(create.body)
    const res = await app.inject({
      method: 'PATCH',
      url: `/parcels/${id}/status`,
      headers: authHeaders,
      payload: { status: 'NOT_A_REAL_STATUS' }
    })
    expect(res.statusCode).toBe(400)
  })
})

describe('GET /parcels/:id/position', () => {
  it('returns 204 when no GPS position available', async () => {
    const create = await app.inject({ method: 'POST', url: '/parcels', headers: authHeaders, payload })
    const { tracking_code } = JSON.parse(create.body)
    const res = await app.inject({ method: 'GET', url: `/parcels/${tracking_code}/position` })
    expect(res.statusCode).toBe(204)
  })
})
