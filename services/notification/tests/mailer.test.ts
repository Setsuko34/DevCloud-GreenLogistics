import { describe, it, expect } from 'vitest'
import { buildMailOptions } from '../src/mailer'

describe('buildMailOptions', () => {
  it('builds correct email options for near_5min event', () => {
    const opts = buildMailOptions({
      parcel_id: 'abc-123',
      event: 'near_5min',
      recipient_email: 'bob@example.com'
    })
    expect(opts.to).toBe('bob@example.com')
    expect(opts.subject).toContain('5 min')
    expect(opts.text).toContain('abc-123')
  })
})
