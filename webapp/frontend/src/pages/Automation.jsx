import React, { useState, useEffect, useCallback } from 'react'
import { api } from '../api/client'

const STATUS_COLOR = {
  PENDING:        '#f0a500',
  REVIEWING:      '#9c27b0',
  REVIEW_FAILED:  '#f44336',
  UPLOADING:      '#667eea',
  UPLOADED:       '#4caf50',
  FAILED:         '#f44336',
}
const STATUS_ICON = {
  PENDING:        '⏳',
  REVIEWING:      '🔍',
  REVIEW_FAILED:  '📋',
  UPLOADING:      '⬆️',
  UPLOADED:       '✅',
  FAILED:         '❌',
}

const CHANNELS = [
  { id: 'en', name: 'EdgeViralHub',  flag: '🇬🇧', color: '#ff4444' },
  { id: 'te', name: 'ManaTeluguDu', flag: '🇮🇳', color: '#ff9900' },
]

export default function Automation() {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  // OAuth setup state per channel
  const [oauthInputs, setOauthInputs] = useState({ en: { clientId: '', clientSecret: '' }, te: { clientId: '', clientSecret: '' } })
  const [oauthLoading, setOauthLoading] = useState({})
  const [oauthMsg, setOauthMsg] = useState({})

  // Upload state per job
  const [publishingJob, setPublishingJob] = useState(null)
  const [publishingAll, setPublishingAll] = useState(false)
  const [actionMsg, setActionMsg] = useState({})

  // Review detail expanded per job
  const [expandedReview, setExpandedReview] = useState(null)

  const load = useCallback(async () => {
    try {
      const res = await api.getAutomationStatus()
      setData(res.data)
      setError('')
    } catch (e) {
      setError('Failed to load automation status: ' + e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
    const interval = setInterval(load, 5000)
    return () => clearInterval(interval)
  }, [load])

  const handleConnect = async (channelId) => {
    const { clientId, clientSecret } = oauthInputs[channelId]
    if (!clientId.trim() || !clientSecret.trim()) {
      setOauthMsg(m => ({ ...m, [channelId]: { type: 'error', text: 'Both Client ID and Client Secret are required.' } }))
      return
    }
    setOauthLoading(l => ({ ...l, [channelId]: true }))
    setOauthMsg(m => ({ ...m, [channelId]: null }))
    try {
      const res = await api.oauthSetup(channelId, clientId.trim(), clientSecret.trim())
      const authUrl = res.data.auth_url
      window.open(authUrl, '_blank', 'noopener,noreferrer')
      setOauthMsg(m => ({ ...m, [channelId]: { type: 'info', text: '🌐 Authorization page opened in new tab. Authorize, then come back — status updates automatically.' } }))
    } catch (e) {
      setOauthMsg(m => ({ ...m, [channelId]: { type: 'error', text: e.response?.data?.detail || e.message } }))
    } finally {
      setOauthLoading(l => ({ ...l, [channelId]: false }))
    }
  }

  const handleDisconnect = async (channelId) => {
    if (!window.confirm(`Disconnect YouTube for ${channelId}? You'll need to re-authorize to upload.`)) return
    try {
      await api.oauthDisconnect(channelId)
      load()
    } catch (e) {
      alert('Error: ' + e.message)
    }
  }

  // One-click: review + upload
  const handlePublish = async (jobId) => {
    setPublishingJob(jobId)
    setActionMsg(m => ({ ...m, [jobId]: { type: 'info', text: '🔍 Starting content review + upload…' } }))
    try {
      await api.autoPublish(jobId)
      setActionMsg(m => ({ ...m, [jobId]: { type: 'info', text: '🔍 Reviewing content — will auto-upload if it passes…' } }))
      load()
    } catch (e) {
      setActionMsg(m => ({ ...m, [jobId]: { type: 'error', text: e.response?.data?.detail || e.message } }))
    } finally {
      setPublishingJob(null)
    }
  }

  // Publish all pending at once
  const handlePublishAll = async () => {
    if (!window.confirm('Auto-publish ALL pending videos?\n\nEach will be reviewed for YouTube policy compliance and auto-uploaded if it passes.')) return
    setPublishingAll(true)
    try {
      const res = await api.autoPublishAll()
      const msg = res.data.message || `Started ${res.data.started?.length || 0} video(s)`
      setActionMsg(m => ({ ...m, _all: { type: 'success', text: `🚀 ${msg}` } }))
      load()
    } catch (e) {
      setActionMsg(m => ({ ...m, _all: { type: 'error', text: e.response?.data?.detail || e.message } }))
    } finally {
      setPublishingAll(false)
    }
  }

  // Force upload after review fail
  const handleForceUpload = async (jobId) => {
    if (!window.confirm('This video FAILED content review.\n\nAre you sure you want to upload it anyway? This may violate YouTube policies.')) return
    setPublishingJob(jobId)
    setActionMsg(m => ({ ...m, [jobId]: { type: 'info', text: '⬆️ Force-uploading…' } }))
    try {
      await api.forceUpload(jobId)
      setActionMsg(m => ({ ...m, [jobId]: { type: 'info', text: '⬆️ Force-upload started…' } }))
      load()
    } catch (e) {
      setActionMsg(m => ({ ...m, [jobId]: { type: 'error', text: e.response?.data?.detail || e.message } }))
    } finally {
      setPublishingJob(null)
    }
  }

  const handleRemove = async (jobId) => {
    if (!window.confirm('Remove this job from the queue?')) return
    try {
      await api.removeFromQueue(jobId)
      load()
    } catch (e) {
      alert('Error: ' + e.message)
    }
  }

  if (loading) return (
    <div><h2>🤖 Automation & Upload</h2>
      <div className="loading"><div className="spinner"></div></div>
    </div>
  )

  const queue = data?.queue || []
  const oauthStatus = data?.oauth_status || {}
  const googleLibsOk = data?.google_libs_available !== false

  const pending   = queue.filter(j => j.status === 'PENDING')
  const reviewing = queue.filter(j => j.status === 'REVIEWING')
  const reviewFailed = queue.filter(j => j.status === 'REVIEW_FAILED')
  const active    = queue.filter(j => j.status === 'UPLOADING')
  const uploaded  = queue.filter(j => j.status === 'UPLOADED')
  const failed    = queue.filter(j => j.status === 'FAILED')

  const anyConnected = Object.values(oauthStatus).some(s => s.connected)

  const CHECK_COLOR = { PASS: '#4caf50', FAIL: '#f44336', WARNING: '#f0a500' }
  const CHECK_ICON  = { PASS: '✅', FAIL: '❌', WARNING: '⚠️' }

  return (
    <div>
      <h2>🤖 Automation & Upload</h2>

      {!googleLibsOk && (
        <div style={{ padding: '1rem', background: '#2a1a1a', border: '1px solid #f44', borderRadius: '8px', marginBottom: '1.5rem', color: '#f88' }}>
          ⚠️ Google API libraries not installed in the backend container. <strong>Rebuild the container</strong> to enable YouTube uploads.
        </div>
      )}

      {error && (
        <div style={{ padding: '0.75rem', background: '#2a1a1a', border: '1px solid #552222', borderRadius: '6px', color: '#f66', marginBottom: '1rem' }}>
          ❌ {error}
        </div>
      )}

      {/* ---- Step 1: YouTube Connect ---- */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div className="card-header">
          <h3>🔗 Step 1 — Connect YouTube Channels</h3>
        </div>
        <div className="card-content">
          <p style={{ color: '#888', fontSize: '0.9rem', marginBottom: '1rem' }}>
            YouTube uploads require OAuth2. Get <strong>Client ID</strong> and <strong>Client Secret</strong> from{' '}
            <strong style={{ color: '#fff' }}>console.cloud.google.com</strong> → APIs &amp; Services → Credentials → OAuth 2.0 Client ID (type: <em>Web application</em>).<br />
            Add <code style={{ color: '#aaa' }}>http://localhost:8000/api/automation/oauth/callback</code> as an authorized redirect URI.
          </p>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.5rem' }}>
            {CHANNELS.map(ch => {
              const status = oauthStatus[ch.id] || {}
              const connected = status.connected
              const msg = oauthMsg[ch.id]
              return (
                <div key={ch.id} style={{ padding: '1.2rem', background: '#1a1a1a', border: `1px solid ${connected ? '#2a5a2a' : '#3a3a3a'}`, borderRadius: '8px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
                    <strong style={{ fontSize: '1rem' }}>{ch.flag} {ch.name}</strong>
                    <span style={{ padding: '0.25rem 0.6rem', borderRadius: '12px', fontSize: '0.8rem', fontWeight: 'bold', background: connected ? '#1a3a1a' : '#3a2a1a', color: connected ? '#4caf50' : '#f0a500' }}>
                      {connected ? '✅ Connected' : '⚠️ Not connected'}
                    </span>
                  </div>

                  {connected ? (
                    <div>
                      <p style={{ color: '#4caf50', fontSize: '0.9rem', marginBottom: '0.75rem' }}>
                        Ready to upload videos to this channel.
                      </p>
                      <button
                        onClick={() => handleDisconnect(ch.id)}
                        style={{ padding: '0.5rem 1rem', background: '#3a1a1a', color: '#f66', border: '1px solid #552222', borderRadius: '4px', cursor: 'pointer', fontSize: '0.85rem' }}
                      >
                        🔓 Disconnect
                      </button>
                    </div>
                  ) : (
                    <div>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginBottom: '0.75rem' }}>
                        <input
                          type="text"
                          placeholder="Client ID (xxxxxxxxxx.apps.googleusercontent.com)"
                          value={oauthInputs[ch.id].clientId}
                          onChange={e => setOauthInputs(o => ({ ...o, [ch.id]: { ...o[ch.id], clientId: e.target.value } }))}
                          style={{ padding: '0.6rem', background: '#2a2a2a', border: '1px solid #444', color: 'white', borderRadius: '4px', fontSize: '0.85rem' }}
                        />
                        <input
                          type="password"
                          placeholder="Client Secret"
                          value={oauthInputs[ch.id].clientSecret}
                          onChange={e => setOauthInputs(o => ({ ...o, [ch.id]: { ...o[ch.id], clientSecret: e.target.value } }))}
                          style={{ padding: '0.6rem', background: '#2a2a2a', border: '1px solid #444', color: 'white', borderRadius: '4px', fontSize: '0.85rem' }}
                        />
                      </div>
                      <button
                        onClick={() => handleConnect(ch.id)}
                        disabled={oauthLoading[ch.id]}
                        style={{ width: '100%', padding: '0.7rem', background: oauthLoading[ch.id] ? '#333' : ch.color, color: 'white', border: 'none', borderRadius: '4px', cursor: oauthLoading[ch.id] ? 'not-allowed' : 'pointer', fontWeight: 'bold' }}
                      >
                        {oauthLoading[ch.id] ? '⏳ Opening…' : '🔗 Connect & Authorize'}
                      </button>
                    </div>
                  )}
                  {msg && (
                    <div style={{ marginTop: '0.75rem', padding: '0.6rem', background: msg.type === 'error' ? '#2a1a1a' : '#1a2a1a', border: `1px solid ${msg.type === 'error' ? '#552' : '#2a5a2a'}`, borderRadius: '4px', fontSize: '0.85rem', color: msg.type === 'error' ? '#f88' : '#8d8' }}>
                      {msg.text}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      </div>

      {/* ---- Step 2: Upload Queue ---- */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
          <h3>📤 Step 2 — Publish Queue</h3>
          <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
            {pending.length > 0 && anyConnected && (
              <button
                onClick={handlePublishAll}
                disabled={publishingAll}
                style={{ padding: '0.5rem 1rem', background: '#1a6a2a', color: 'white', border: 'none', borderRadius: '5px', cursor: publishingAll ? 'not-allowed' : 'pointer', fontWeight: 'bold', fontSize: '0.9rem' }}
              >
                {publishingAll ? '⏳ Starting…' : `🚀 Publish All (${pending.length})`}
              </button>
            )}
            <button onClick={load} style={{ padding: '0.4rem 0.9rem', background: '#2a2a2a', color: '#aaa', border: '1px solid #444', borderRadius: '4px', cursor: 'pointer', fontSize: '0.85rem' }}>🔄 Refresh</button>
          </div>
        </div>
        {actionMsg._all && (
          <div style={{ margin: '0 1rem', padding: '0.6rem', background: actionMsg._all.type === 'error' ? '#2a1a1a' : '#1a2a1a', border: `1px solid ${actionMsg._all.type === 'error' ? '#552' : '#2a5a2a'}`, borderRadius: '4px', fontSize: '0.85rem', color: actionMsg._all.type === 'error' ? '#f88' : '#8d8' }}>
            {actionMsg._all.text}
          </div>
        )}
        <div className="card-content">
          {queue.length === 0 ? (
            <div style={{ padding: '2rem', textAlign: 'center', color: '#666' }}>
              <p>No videos in the upload queue.</p>
              <p style={{ fontSize: '0.85rem', marginTop: '0.5rem' }}>Approve a video from the Review tab — it will appear here.</p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
              {/* Active uploads first */}
              {[...reviewing, ...active, ...reviewFailed, ...pending, ...failed, ...uploaded].map(job => {
                const chInfo = CHANNELS.find(c => c.id === job.channel?.toLowerCase()) || CHANNELS[0]
                const chConnected = oauthStatus[job.channel?.toLowerCase()]?.connected
                const msg = actionMsg[job.job_id]
                const isUploading = job.status === 'UPLOADING'
                const isUploaded = job.status === 'UPLOADED'
                const isFailed = job.status === 'FAILED'
                const isPending = job.status === 'PENDING'
                const isReviewing = job.status === 'REVIEWING'
                const isReviewFailed = job.status === 'REVIEW_FAILED'
                const reviewData = job.last_review?.review_data

                return (
                  <div key={job.job_id} style={{ padding: '1rem', background: '#1a1a1a', border: `1px solid ${STATUS_COLOR[job.status] || '#333'}33`, borderRadius: '8px', borderLeft: `4px solid ${STATUS_COLOR[job.status] || '#555'}` }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '0.5rem' }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.3rem', flexWrap: 'wrap' }}>
                          <span style={{ fontSize: '1.1rem' }}>{STATUS_ICON[job.status] || '❓'}</span>
                          <strong style={{ color: STATUS_COLOR[job.status] || '#aaa' }}>{job.status === 'REVIEW_FAILED' ? 'REVIEW FAILED' : job.status}</strong>
                          <span style={{ color: '#666', fontSize: '0.85rem' }}>{chInfo.flag} {chInfo.name}</span>
                        </div>
                        <p style={{ color: '#e0e0e0', fontWeight: '500', marginBottom: '0.25rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {job.title || 'No title'}
                        </p>
                        <p style={{ color: '#666', fontSize: '0.8rem' }}>Job: {job.job_id}</p>
                        {job.approved_at && (
                          <p style={{ color: '#555', fontSize: '0.8rem' }}>Approved: {new Date(job.approved_at).toLocaleString()}</p>
                        )}
                        {isUploaded && job.youtube_url && (
                          <a href={job.youtube_url} target="_blank" rel="noopener noreferrer" style={{ color: '#4caf50', fontSize: '0.85rem', display: 'inline-block', marginTop: '0.3rem' }}>
                            ▶ Watch on YouTube →
                          </a>
                        )}
                        {isFailed && job.error && (
                          <p style={{ color: '#f88', fontSize: '0.8rem', marginTop: '0.3rem' }}>Error: {job.error}</p>
                        )}
                        {isReviewing && (
                          <div style={{ marginTop: '0.5rem' }}>
                            <div style={{ height: '6px', background: '#0a0a0a', borderRadius: '3px', overflow: 'hidden', width: '200px' }}>
                              <div style={{ height: '100%', background: 'linear-gradient(90deg, #9c27b0, #e040fb, #9c27b0)', backgroundSize: '200% 100%', width: '100%', animation: 'shimmer 2s infinite', borderRadius: '3px' }} />
                            </div>
                            <p style={{ color: '#ce93d8', fontSize: '0.8rem', marginTop: '0.25rem' }}>🔍 Checking content against YouTube policies… will auto-upload if clean.</p>
                          </div>
                        )}
                        {isUploading && (
                          <div style={{ marginTop: '0.5rem' }}>
                            <div style={{ height: '6px', background: '#0a0a0a', borderRadius: '3px', overflow: 'hidden', width: '200px' }}>
                              <div style={{ height: '100%', background: 'linear-gradient(90deg, #667eea, #764ba2, #667eea)', backgroundSize: '200% 100%', width: '100%', animation: 'shimmer 2s infinite', borderRadius: '3px' }} />
                            </div>
                            <p style={{ color: '#667eea', fontSize: '0.8rem', marginTop: '0.25rem' }}>⬆️ Review passed — uploading to YouTube…</p>
                          </div>
                        )}
                        {isReviewFailed && (
                          <div style={{ marginTop: '0.5rem' }}>
                            <p style={{ color: '#f88', fontSize: '0.85rem' }}>❌ {job.review_error || 'Content did not pass YouTube policy review.'}</p>
                            {reviewData && (
                              <button
                                onClick={() => setExpandedReview(expandedReview === job.job_id ? null : job.job_id)}
                                style={{ marginTop: '0.4rem', background: 'transparent', color: '#aaa', border: '1px solid #444', borderRadius: '4px', padding: '0.3rem 0.7rem', cursor: 'pointer', fontSize: '0.8rem' }}
                              >
                                {expandedReview === job.job_id ? '▾ Hide Details' : '▸ View Review Details'}
                              </button>
                            )}
                          </div>
                        )}
                      </div>

                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', alignItems: 'flex-end' }}>
                        {isPending && (
                          <>
                            {!chConnected && (
                              <p style={{ color: '#f0a500', fontSize: '0.75rem', textAlign: 'right', maxWidth: '140px' }}>
                                ⚠️ Connect {chInfo.name} first (Step 1)
                              </p>
                            )}
                            <button
                              onClick={() => handlePublish(job.job_id)}
                              disabled={!chConnected || publishingJob === job.job_id}
                              style={{ padding: '0.6rem 1.1rem', background: chConnected ? '#1a6a2a' : '#2a2a2a', color: chConnected ? 'white' : '#666', border: 'none', borderRadius: '4px', cursor: chConnected ? 'pointer' : 'not-allowed', fontWeight: 'bold', fontSize: '0.9rem', whiteSpace: 'nowrap' }}
                            >
                              {publishingJob === job.job_id ? '⏳ Starting…' : '🚀 Publish'}
                            </button>
                          </>
                        )}
                        {isReviewFailed && (
                          <button
                            onClick={() => handleForceUpload(job.job_id)}
                            disabled={publishingJob === job.job_id}
                            style={{ padding: '0.6rem 1rem', background: '#4a1a1a', color: '#f88', border: '1px solid #552', borderRadius: '4px', cursor: 'pointer', fontSize: '0.85rem', fontWeight: 'bold' }}
                          >
                            ⚠️ Override & Upload
                          </button>
                        )}
                        {isFailed && (
                          <button
                            onClick={() => handlePublish(job.job_id)}
                            disabled={publishingJob === job.job_id}
                            style={{ padding: '0.6rem 1rem', background: '#4a1a1a', color: '#f88', border: '1px solid #552', borderRadius: '4px', cursor: 'pointer', fontSize: '0.85rem' }}
                          >
                            🔁 Retry
                          </button>
                        )}
                        {(isFailed || isPending || isUploaded || isReviewFailed) && (
                          <button
                            onClick={() => handleRemove(job.job_id)}
                            style={{ padding: '0.4rem 0.7rem', background: 'transparent', color: '#555', border: '1px solid #333', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem' }}
                          >
                            🗑 Remove
                          </button>
                        )}
                      </div>
                    </div>

                    {/* Expandable review details for REVIEW_FAILED */}
                    {isReviewFailed && expandedReview === job.job_id && reviewData && (
                      <div style={{ marginTop: '0.75rem', padding: '1rem', background: '#111', border: '1px solid #333', borderRadius: '6px' }}>
                        {/* Overall */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem', padding: '0.6rem 0.8rem', background: '#2a0a0a', border: '1px solid #f4433644', borderRadius: '6px' }}>
                          <span style={{ fontSize: '1.4rem' }}>{CHECK_ICON[reviewData.overall] || '❓'}</span>
                          <div>
                            <div style={{ fontWeight: 'bold', color: CHECK_COLOR[reviewData.overall], fontSize: '0.95rem' }}>Overall: {reviewData.overall}</div>
                            <div style={{ color: '#ccc', fontSize: '0.8rem' }}>{reviewData.summary}</div>
                          </div>
                        </div>

                        {/* Checks */}
                        {reviewData.checks?.length > 0 && (
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem', marginBottom: '0.75rem' }}>
                            {reviewData.checks.map((c, i) => (
                              <div key={i} style={{ display: 'flex', gap: '0.5rem', padding: '0.4rem 0.6rem', borderRadius: '4px', background: '#0a0a0a' }}>
                                <span style={{ fontSize: '0.85rem' }}>{CHECK_ICON[c.status] || '❓'}</span>
                                <div style={{ flex: 1 }}>
                                  <span style={{ fontWeight: 600, color: CHECK_COLOR[c.status] || '#ccc', fontSize: '0.85rem' }}>{c.name || c.label}</span>
                                  {c.detail && <span style={{ color: '#888', fontSize: '0.8rem', marginLeft: '0.5rem' }}>— {c.detail}</span>}
                                </div>
                              </div>
                            ))}
                          </div>
                        )}

                        {/* Issues */}
                        {reviewData.issues?.length > 0 && (
                          <div style={{ padding: '0.5rem 0.75rem', background: '#1f1010', borderRadius: '4px', marginBottom: '0.5rem' }}>
                            <div style={{ fontSize: '0.75rem', color: '#f88', textTransform: 'uppercase', marginBottom: '0.3rem' }}>Issues</div>
                            <ul style={{ margin: 0, paddingLeft: '1.1rem', color: '#f99', fontSize: '0.8rem', lineHeight: 1.6 }}>
                              {reviewData.issues.map((issue, i) => <li key={i}>{issue}</li>)}
                            </ul>
                          </div>
                        )}

                        {/* Suggestions */}
                        {reviewData.suggestions?.length > 0 && (
                          <div style={{ padding: '0.5rem 0.75rem', background: '#101820', borderRadius: '4px' }}>
                            <div style={{ fontSize: '0.75rem', color: '#88c', textTransform: 'uppercase', marginBottom: '0.3rem' }}>Suggestions</div>
                            <ul style={{ margin: 0, paddingLeft: '1.1rem', color: '#aac', fontSize: '0.8rem', lineHeight: 1.6 }}>
                              {reviewData.suggestions.map((s, i) => <li key={i}>{s}</li>)}
                            </ul>
                          </div>
                        )}
                      </div>
                    )}

                    {msg && (
                      <div style={{ marginTop: '0.75rem', padding: '0.6rem', background: msg.type === 'error' ? '#2a1a1a' : '#1a2a1a', border: `1px solid ${msg.type === 'error' ? '#552' : '#2a5a2a'}`, borderRadius: '4px', fontSize: '0.85rem', color: msg.type === 'error' ? '#f88' : '#8d8' }}>
                        {msg.text}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>

      {/* ---- How It Works ---- */}
      <div className="card">
        <div className="card-header"><h3>ℹ️ How It Works</h3></div>
        <div className="card-content">
          <ol style={{ paddingLeft: '1.5rem', lineHeight: '1.8' }}>
            <li><strong>Connect</strong> — Enter OAuth2 credentials for each channel (one-time setup)</li>
            <li><strong>Authorize</strong> — Click "Connect & Authorize" → approve on Google</li>
            <li><strong>Publish</strong> — Click "🚀 Publish" (or "Publish All") → the system automatically:
              <ul style={{ paddingLeft: '1.5rem', lineHeight: '1.8', color: '#aaa' }}>
                <li>🔍 <strong>Reviews content</strong> against YouTube's policies (copyright, community guidelines, spam, etc.)</li>
                <li>✅ If review <strong>passes</strong> → auto-uploads to YouTube as <em>Private</em></li>
                <li>❌ If review <strong>fails</strong> → stops and shows issues. You can fix or override.</li>
              </ul>
            </li>
            <li><strong>Go Live</strong> — Open YouTube Studio and change visibility when ready</li>
          </ol>
          <div style={{ marginTop: '1rem', padding: '1rem', background: '#1a2a1a', border: '1px solid #2a4a2a', borderRadius: '6px', fontSize: '0.85rem', color: '#aaa' }}>
            <p><strong style={{ color: '#fff' }}>OAuth2 Setup (one-time per channel):</strong></p>
            <ol style={{ paddingLeft: '1.5rem', lineHeight: '1.9' }}>
              <li>Go to <strong>console.cloud.google.com</strong> → Your project</li>
              <li>APIs &amp; Services → Credentials → Create OAuth 2.0 Client ID</li>
              <li>Application type: <strong>Web application</strong></li>
              <li>Authorized redirect URIs: add <code>http://localhost:8000/api/automation/oauth/callback</code></li>
              <li>Download/copy the Client ID and Client Secret → paste above</li>
            </ol>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes shimmer {
          0% { background-position: -200% 0; }
          100% { background-position: 200% 0; }
        }
      `}</style>
    </div>
  )
}
