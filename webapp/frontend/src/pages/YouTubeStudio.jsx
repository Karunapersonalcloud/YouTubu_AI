import React, { useState, useEffect, useCallback } from 'react'

const API = 'http://localhost:8000'

function fmt(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K'
  return String(n)
}

function timeAgo(iso) {
  const diff = Date.now() - new Date(iso).getTime()
  const days = Math.floor(diff / 86400000)
  if (days === 0) return 'Today'
  if (days === 1) return 'Yesterday'
  if (days < 30) return `${days}d ago`
  const months = Math.floor(days / 30)
  if (months < 12) return `${months}mo ago`
  return `${Math.floor(months / 12)}y ago`
}

export default function YouTubeStudio({ channel }) {
  const channels = {
    edgeviralhub: {
      name: 'EdgeViralHub',
      language: 'English',
      flag: '🇬🇧',
      niche: 'AI tools, productivity, career skills, make-money-with-ai',
      color: '#ff4444',
      defaultChannelId: 'UCUrRoG8iJcaG47hypsiS40g',
      storageKey: 'channelId_edgeviralhub'
    },
    manatelugodu: {
      name: 'ManaTeluguDu',
      language: 'Telugu',
      flag: '🇮🇳',
      niche: 'AI explained in Telugu, career, motivation, practical tech awareness',
      color: '#ff9900',
      defaultChannelId: 'UCpB9tw4kZASNZ4AkictDgUA',
      storageKey: 'channelId_manatelugodu'
    }
  }

  const ch = channels[channel] || channels['edgeviralhub']

  const [channelId, setChannelId] = useState(() =>
    localStorage.getItem(ch.storageKey) || ch.defaultChannelId
  )
  const [inputValue, setInputValue] = useState(() =>
    localStorage.getItem(ch.storageKey) || ch.defaultChannelId
  )
  const [saved, setSaved] = useState(false)

  // YouTube API key state
  const [apiKey, setApiKey] = useState(() => localStorage.getItem('yt_api_key') || '')
  const [apiKeyInput, setApiKeyInput] = useState(() => localStorage.getItem('yt_api_key') || '')
  const [apiKeySaved, setApiKeySaved] = useState(false)

  // Stats state
  const [stats, setStats] = useState(null)
  const [statsLoading, setStatsLoading] = useState(false)
  const [statsError, setStatsError] = useState('')
  const [lastFetched, setLastFetched] = useState(null)

  const studioBase = `https://studio.youtube.com/channel/${channelId}`
  const channelPageUrl = `https://www.youtube.com/channel/${channelId}`

  const saveChannelId = () => {
    let id = inputValue.trim()
    const match = id.match(/channel\/(UC[a-zA-Z0-9_-]+)/)
    if (match) id = match[1]
    if (id.startsWith('UC') && id.length > 10) {
      localStorage.setItem(ch.storageKey, id)
      setChannelId(id)
      setInputValue(id)
      setSaved(true)
      setStats(null)
      setTimeout(() => setSaved(false), 2000)
    } else {
      alert('Please enter a valid Channel ID (starts with UC...) or paste the full Studio URL')
    }
  }

  const saveApiKey = () => {
    const key = apiKeyInput.trim()
    if (key.length < 20) {
      alert('Please enter a valid YouTube Data API key')
      return
    }
    localStorage.setItem('yt_api_key', key)
    setApiKey(key)
    setApiKeySaved(true)
    setTimeout(() => setApiKeySaved(false), 2000)
  }

  const fetchStats = useCallback(async () => {
    if (!apiKey) return
    setStatsLoading(true)
    setStatsError('')
    try {
      const res = await fetch(`${API}/api/youtube-stats/${channelId}?api_key=${encodeURIComponent(apiKey)}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data.detail || 'API error')
      setStats(data)
      setLastFetched(new Date())
    } catch (e) {
      setStatsError(e.message)
    } finally {
      setStatsLoading(false)
    }
  }, [apiKey, channelId])

  // Auto-fetch when API key and channelId are ready
  useEffect(() => {
    if (apiKey && channelId) fetchStats()
  }, [apiKey, channelId])

  const openUrl = (url) => window.open(url, '_blank', 'noopener,noreferrer')

  const quickLinks = [
    { label: '📊 Analytics', url: `${studioBase}/analytics` },
    { label: '🎬 Videos', url: `${studioBase}/videos` },
    { label: '💬 Comments', url: `${studioBase}/comments` },
    { label: '💰 Monetization', url: `${studioBase}/monetization` },
    { label: '📅 Scheduled', url: `${studioBase}/videos?filter=%5B%5B2%2C%5B7%5D%5D%5D` },
    { label: '⚙️ Settings', url: `${studioBase}/settings` },
  ]

  return (
    <div>
      <h2>{ch.flag} {ch.name} — YouTube Studio</h2>

      {/* API Key Setup */}
      <div className="card" style={{ marginBottom: '1.5rem', border: `1px solid ${apiKey ? '#2a4a2a' : '#4a3a1a'}` }}>
        <div className="card-header">
          <h3>🔑 YouTube Data API Key {apiKey && <span style={{ color: '#4caf50', fontSize: '0.8rem', fontWeight: 'normal' }}>✅ configured</span>}</h3>
        </div>
        <div className="card-content">
          {!apiKey ? (
            <div style={{ padding: '0.75rem', background: '#2a2a10', border: '1px solid #55441a', borderRadius: '6px', marginBottom: '1rem', fontSize: '0.9rem', color: '#ccc' }}>
              <strong style={{ color: '#f0a500' }}>⚠️ No API key set.</strong> Get a free key from{' '}
              <strong style={{ color: '#fff' }}>console.cloud.google.com</strong> → Enable "YouTube Data API v3" → Create API Key.
            </div>
          ) : null}
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <input
              type="password"
              value={apiKeyInput}
              onChange={(e) => setApiKeyInput(e.target.value)}
              placeholder="AIza... (YouTube Data API v3 key)"
              style={{ flex: 1, padding: '0.75rem', background: '#2a2a2a', border: '1px solid #444', color: 'white', borderRadius: '4px', fontSize: '0.9rem' }}
              onKeyDown={(e) => e.key === 'Enter' && saveApiKey()}
            />
            <button
              onClick={saveApiKey}
              style={{ padding: '0.75rem 1.2rem', background: apiKeySaved ? '#2a5a2a' : '#1a6a8a', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold', minWidth: '80px' }}
            >
              {apiKeySaved ? '✅ Saved!' : 'Save Key'}
            </button>
          </div>
          <p style={{ color: '#666', fontSize: '0.8rem', marginTop: '0.5rem', margin: '0.5rem 0 0' }}>
            Key is stored in your browser only — never sent anywhere except YouTube's API.
          </p>
        </div>
      </div>

      {/* Live Channel Stats */}
      {apiKey && (
        <div className="card" style={{ marginBottom: '1.5rem', border: `1px solid ${ch.color}44` }}>
          <div className="card-header" style={{ borderLeft: `4px solid ${ch.color}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h3>📈 Live Channel Stats</h3>
            <button
              onClick={fetchStats}
              disabled={statsLoading}
              style={{ padding: '0.4rem 0.9rem', background: '#2a2a2a', color: '#aaa', border: '1px solid #444', borderRadius: '4px', cursor: statsLoading ? 'not-allowed' : 'pointer', fontSize: '0.85rem' }}
            >
              {statsLoading ? '⏳ Loading…' : '🔄 Refresh'}
            </button>
          </div>
          <div className="card-content">
            {statsError && (
              <div style={{ padding: '0.75rem', background: '#2a1a1a', border: '1px solid #552222', borderRadius: '6px', color: '#ff6666', fontSize: '0.9rem', marginBottom: '1rem' }}>
                ❌ {statsError}
              </div>
            )}
            {statsLoading && !stats && (
              <div style={{ textAlign: 'center', padding: '2rem', color: '#666' }}>⏳ Fetching stats…</div>
            )}
            {stats && (
              <>
                {/* Stat cards */}
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '1rem', marginBottom: '1.5rem' }}>
                  {[
                    { label: '👥 Subscribers', value: fmt(stats.subscribers) },
                    { label: '👁️ Total Views', value: fmt(stats.views) },
                    { label: '🎬 Videos', value: fmt(stats.video_count) },
                  ].map(s => (
                    <div key={s.label} style={{ padding: '1rem', background: '#1a1a1a', border: `1px solid ${ch.color}33`, borderRadius: '8px', textAlign: 'center' }}>
                      <div style={{ fontSize: '0.8rem', color: '#888', marginBottom: '0.4rem' }}>{s.label}</div>
                      <div style={{ fontSize: '1.8rem', fontWeight: 'bold', color: ch.color }}>{s.value}</div>
                    </div>
                  ))}
                </div>

                {/* Recent videos */}
                {stats.recent_videos?.length > 0 && (
                  <>
                    <p style={{ color: '#aaa', fontWeight: 'bold', marginBottom: '0.75rem' }}>🕐 Recent Uploads</p>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.6rem' }}>
                      {stats.recent_videos.map(v => (
                        <div
                          key={v.id}
                          onClick={() => openUrl(`https://www.youtube.com/watch?v=${v.id}`)}
                          style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', padding: '0.6rem', background: '#1a1a1a', border: '1px solid #2a2a2a', borderRadius: '6px', cursor: 'pointer' }}
                          onMouseEnter={e => e.currentTarget.style.borderColor = ch.color + '66'}
                          onMouseLeave={e => e.currentTarget.style.borderColor = '#2a2a2a'}
                        >
                          {v.thumbnail && (
                            <img src={v.thumbnail} alt="" style={{ width: '80px', height: '45px', objectFit: 'cover', borderRadius: '4px', flexShrink: 0 }} />
                          )}
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ color: '#e0e0e0', fontSize: '0.9rem', fontWeight: '500', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {v.title}
                            </div>
                            <div style={{ color: '#666', fontSize: '0.8rem', marginTop: '0.2rem' }}>
                              👁️ {fmt(v.views)} &nbsp;·&nbsp; 👍 {fmt(v.likes)} &nbsp;·&nbsp; 💬 {fmt(v.comments)} &nbsp;·&nbsp; {timeAgo(v.published_at)}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  </>
                )}

                {lastFetched && (
                  <p style={{ color: '#555', fontSize: '0.8rem', marginTop: '1rem', textAlign: 'right' }}>
                    Last updated: {lastFetched.toLocaleTimeString()}
                  </p>
                )}
              </>
            )}
          </div>
        </div>
      )}

      {/* Channel ID */}
      <div className="card" style={{ marginBottom: '1.5rem', border: '1px solid #2a4a2a' }}>
        <div className="card-header">
          <h3>🔗 Channel ID</h3>
        </div>
        <div className="card-content">
          <div style={{ marginBottom: '1rem', padding: '0.75rem', background: '#1a2a1a', borderRadius: '6px' }}>
            <span style={{ color: '#4caf50', fontSize: '0.9rem' }}>
              ✅ Channel ID: <code style={{ color: '#aaa' }}>{channelId}</code>
            </span>
          </div>
          <p style={{ color: '#aaa', fontSize: '0.9rem', marginBottom: '0.75rem' }}>
            Update if needed (paste full Studio URL or just the ID):
          </p>
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <input
              type="text"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              placeholder="UCxxxxxxxxxxxxxxxxxx  or  https://studio.youtube.com/channel/UC..."
              style={{ flex: 1, padding: '0.75rem', background: '#2a2a2a', border: '1px solid #444', color: 'white', borderRadius: '4px', fontSize: '0.9rem' }}
              onKeyDown={(e) => e.key === 'Enter' && saveChannelId()}
            />
            <button
              onClick={saveChannelId}
              style={{ padding: '0.75rem 1.2rem', background: saved ? '#2a5a2a' : ch.color, color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold', minWidth: '80px' }}
            >
              {saved ? '✅ Saved!' : 'Update'}
            </button>
          </div>
        </div>
      </div>

      {/* Studio Launch */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div className="card-header" style={{ borderLeft: `4px solid ${ch.color}` }}>
          <h3>{ch.flag} {ch.name}</h3>
        </div>
        <div className="card-content">
          <div style={{ marginBottom: '1.5rem' }}>
            <p><strong>Language:</strong> {ch.language}</p>
            <p><strong>Niche:</strong> {ch.niche}</p>
          </div>
          <button
            onClick={() => openUrl(studioBase)}
            style={{ width: '100%', padding: '1.2rem', fontSize: '1.2rem', fontWeight: 'bold', background: `linear-gradient(135deg, ${ch.color}, #cc0000)`, color: 'white', border: 'none', borderRadius: '8px', cursor: 'pointer', marginBottom: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.75rem' }}
          >
            <span style={{ fontSize: '1.5rem' }}>▶</span>
            Open YouTube Studio — {ch.name}
            <span style={{ fontSize: '0.85rem', opacity: 0.85 }}>(opens in new tab)</span>
          </button>
          <button
            onClick={() => openUrl(channelPageUrl)}
            style={{ width: '100%', padding: '0.8rem', fontSize: '1rem', fontWeight: 'bold', background: '#2a2a2a', color: '#ccc', border: '1px solid #444', borderRadius: '8px', cursor: 'pointer', marginBottom: '1.5rem' }}
          >
            👁️ View Public Channel Page
          </button>
          <p style={{ marginBottom: '0.75rem', color: '#aaa', fontWeight: 'bold' }}>Quick Links:</p>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '0.75rem' }}>
            {quickLinks.map((link) => (
              <button
                key={link.label}
                onClick={() => openUrl(link.url)}
                style={{ padding: '0.7rem', background: '#1a1a2e', color: '#ccc', border: '1px solid #333', borderRadius: '6px', cursor: 'pointer', fontSize: '0.9rem', textAlign: 'center' }}
              >
                {link.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div style={{ padding: '1rem', background: '#1a2a1a', border: '1px solid #2a4a2a', borderRadius: '8px', color: '#aaa', fontSize: '0.9rem' }}>
        <p style={{ margin: 0 }}>
          ℹ️ Make sure you are logged into the correct Google account for <strong style={{ color: '#fff' }}>{ch.name}</strong> before clicking.
        </p>
      </div>
    </div>
  )
}
