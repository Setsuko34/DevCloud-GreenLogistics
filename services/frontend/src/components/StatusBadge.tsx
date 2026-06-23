const COLORS: Record<string, string> = {
  CREATED:    'bg-gray-100 text-gray-800',
  IN_TRANSIT: 'bg-blue-100 text-blue-800',
  NEAR:       'bg-yellow-100 text-yellow-800',
  DELIVERED:  'bg-green-100 text-green-800',
}

export function StatusBadge({ status }: { status: string }) {
  const cls = COLORS[status] ?? 'bg-gray-100 text-gray-800'
  return (
    <span className={`inline-block px-2 py-1 rounded text-sm font-semibold ${cls}`}>
      {status}
    </span>
  )
}
