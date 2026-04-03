import React, { useState, useEffect } from 'react'
import { api } from '../api/client'

export default function Generate({ onGenerated }) {
  const [channels, setChannels] = useState([])
  const [selectedChannel, setSelectedChannel] = useState('EN')
  const [longDuration, setLongDuration] = useState(15)
  const [longDurationInput, setLongDurationInput] = useState('15')
  const [shortDuration, setShortDuration] = useState(1)
  const [shortDurationInput, setShortDurationInput] = useState('1')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [progress, setProgress] = useState(0)
  const [progressTitle, setProgressTitle] = useState('')
  const [pollIntervalId, setPollIntervalId] = useState(null)

  React.useEffect(() => {
    loadChannels()
    // Restore progress from localStorage on mount
    restoreProgressState()
  }, [])

  // Save progress state to localStorage whenever it changes
  useEffect(() => {
    if (loading && progress > 0) {
      localStorage.setItem('generationProgress', JSON.stringify({
        loading,
        progress,
        progressTitle,
        selectedChannel,
        pollStartTime: Date.now()
      }))
    }
  }, [loading, progress, progressTitle, selectedChannel])

  const restoreProgressState = () => {
    const saved = localStorage.getItem('generationProgress')
    if (saved) {
      try {
        const state = JSON.parse(saved)
        // If generation was in progress, restore it
        if (state.loading && state.progress > 0 && state.progress < 100) {
          setLoading(true)
          setProgress(state.progress)
          setProgressTitle(state.progressTitle)
          setSelectedChannel(state.selectedChannel)
          // Resume polling
          resumePolling(state.selectedChannel)
        }
      } catch (err) {
        console.error('Failed to restore progress:', err)
      }
    }
  }

  const resumePolling = (channel) => {
    let initialReviewCount = 0

    // Get initial count
    api.getStatus().then(res => {
      initialReviewCount = res.data.counts.ready_for_review
    }).catch(err => console.error('Failed to get initial status'))

    // Derive pollCount from actual elapsed time since generation started
    const startedAt = parseInt(localStorage.getItem('generationStartedAt') || '0')
    let pollCount = startedAt > 0
      ? Math.max(0, Math.floor((Date.now() - startedAt) / 10000) - 1)
      : 60  // fallback: assume ~10 min in
    let videoFound = false

    const interval = setInterval(async () => {
      pollCount++
      const elapsedSeconds = pollCount * 10
      let calculatedProgress

      if (elapsedSeconds < 120) {
        setProgressTitle('🚀 Starting generation pipeline...')
        calculatedProgress = Math.min(8, 5 + (elapsedSeconds / 120) * 3)
      } else if (elapsedSeconds < 900) {
        setProgressTitle('📝 Step 1/3: Generating script with Ollama...')
        calculatedProgress = Math.min(25, 8 + ((elapsedSeconds - 120) / 780) * 17)
      } else if (elapsedSeconds < 2400) {
        setProgressTitle('🎤 Step 2/3: Creating audio narration with Edge-TTS...')
        calculatedProgress = Math.min(55, 25 + ((elapsedSeconds - 900) / 1500) * 30)
      } else if (elapsedSeconds < 6000) {
        setProgressTitle('🎬 Step 3/3: Composing video with FFmpeg...')
        calculatedProgress = Math.min(92, 55 + ((elapsedSeconds - 2400) / 3600) * 37)
      } else {
        setProgressTitle('✨ Finalizing and saving video files...')
        calculatedProgress = Math.min(95, 92 + 0.005 * ((elapsedSeconds - 6000) / 60))
      }

      setProgress(Math.min(calculatedProgress, 95))

      try {
        const statusRes = await api.getStatus()
        const currentReviewCount = statusRes.data.counts.ready_for_review

        if (currentReviewCount > initialReviewCount && !videoFound) {
          videoFound = true
          clearInterval(interval)
          setProgress(100)
          setProgressTitle('✅ Generation Complete! Video ready for review...')
          localStorage.removeItem('generationProgress')
          localStorage.removeItem('generationStartedAt')

          setTimeout(() => {
            setLoading(false)
            onGenerated()
          }, 2000)
          return
        }
      } catch (err) {
        console.error('Poll error:', err)
      }

      if (pollCount >= 720) {  // 2-hour timeout
        clearInterval(interval)
        setLoading(false)
        setError('⏱️ Generation timeout exceeded (2 hours). Please check logs.')
        localStorage.removeItem('generationProgress')
        localStorage.removeItem('generationStartedAt')
      }
    }, 10000)

    setPollIntervalId(interval)
  }

  const loadChannels = async () => {
    try {
      const res = await api.getChannels()
      const chList = res.data.channels || []
      setChannels(chList)
      if (chList.length > 0) {
        setSelectedChannel(chList[0].id)
      }
    } catch (err) {
      setError('Failed to load channels')
    }
  }

  const handleLongDurationChange = (e) => {
    const val = e.target.value
    // Allow empty string and digits only
    if (val === '' || /^\d+$/.test(val)) {
      setLongDurationInput(val)
    }
  }

  const handleLongDurationBlur = () => {
    let num = parseInt(longDurationInput)
    if (isNaN(num) || longDurationInput === '') {
      setLongDurationInput('15')
      setLongDuration(15)
    } else if (num < 1) {
      setLongDurationInput('1')
      setLongDuration(1)
    } else if (num > 30) {
      setLongDurationInput('30')
      setLongDuration(30)
    } else {
      setLongDuration(num)
    }
  }

  const handleShortDurationChange = (e) => {
    const val = e.target.value
    // Allow empty string and digits only
    if (val === '' || /^\d+$/.test(val)) {
      setShortDurationInput(val)
    }
  }

  const handleShortDurationBlur = () => {
    let num = parseInt(shortDurationInput)
    if (isNaN(num) || shortDurationInput === '') {
      setShortDurationInput('1')
      setShortDuration(1)
    } else if (num < 1) {
      setShortDurationInput('1')
      setShortDuration(1)
    } else if (num > 10) {
      setShortDurationInput('10')
      setShortDuration(10)
    } else {
      setShortDuration(num)
    }
  }

  const handleGenerate = async () => {
    if (!selectedChannel) {
      setError('Please select a channel')
      return
    }

    if (longDuration < 1 || longDuration > 30) {
      setError('Long video duration must be between 1 and 30 minutes')
      return
    }

    if (shortDuration < 1 || shortDuration > 10) {
      setError('Short video duration must be between 1 and 10 minutes')
      return
    }

    setLoading(true)
    setError('')
    setMessage('')
    setProgress(5)
    setProgressTitle(`🚀 Starting generation for ${selectedChannel}...`)

    // Record exact start time so resume polling can derive correct pollCount
    const generationStartedAt = Date.now()
    localStorage.setItem('generationStartedAt', String(generationStartedAt))

    // Get initial review count
    let initialReviewCount = 0
    try {
      const statusRes = await api.getStatus()
      initialReviewCount = statusRes.data.counts.ready_for_review
    } catch (err) {
      console.error('Failed to get initial status')
    }

    try {
      const res = await api.generateContent(selectedChannel, longDuration, shortDuration)

      setProgressTitle('📝 Step 1/3: Generating script with Ollama...')
      setMessage('✅ Content generation started!')

      let pollCount = 0
      const maxPolls = 720  // 2-hour timeout
      let videoFound = false

      const pollInterval = setInterval(async () => {
        pollCount++
        const elapsedSeconds = pollCount * 10
        let calculatedProgress

        if (elapsedSeconds < 120) {
          setProgressTitle('🚀 Starting generation pipeline...')
          calculatedProgress = Math.min(8, 5 + (elapsedSeconds / 120) * 3)
        } else if (elapsedSeconds < 900) {
          setProgressTitle('📝 Step 1/3: Generating script with Ollama...')
          calculatedProgress = Math.min(25, 8 + ((elapsedSeconds - 120) / 780) * 17)
        } else if (elapsedSeconds < 2400) {
          setProgressTitle('🎤 Step 2/3: Creating audio narration with Edge-TTS...')
          calculatedProgress = Math.min(55, 25 + ((elapsedSeconds - 900) / 1500) * 30)
        } else if (elapsedSeconds < 6000) {
          setProgressTitle('🎬 Step 3/3: Composing video with FFmpeg...')
          calculatedProgress = Math.min(92, 55 + ((elapsedSeconds - 2400) / 3600) * 37)
        } else {
          setProgressTitle('✨ Finalizing and saving video files...')
          calculatedProgress = Math.min(95, 92 + 0.005 * ((elapsedSeconds - 6000) / 60))
        }

        setProgress(Math.min(calculatedProgress, 95))

        try {
          const statusRes = await api.getStatus()
          const currentReviewCount = statusRes.data.counts.ready_for_review

          if (currentReviewCount > initialReviewCount && !videoFound) {
            videoFound = true
            clearInterval(pollInterval)
            setProgress(100)
            setProgressTitle('✅ Generation Complete! Video ready for review...')
            localStorage.removeItem('generationProgress')
            localStorage.removeItem('generationStartedAt')

            setTimeout(() => {
              setLoading(false)
              onGenerated()
            }, 2000)
            return
          }
        } catch (err) {
          console.error('Poll error:', err)
        }

        if (pollCount >= maxPolls) {
          clearInterval(pollInterval)
          setLoading(false)
          setError('⏱️ Generation timeout exceeded (2 hours). Please check logs.')
          localStorage.removeItem('generationProgress')
          localStorage.removeItem('generationStartedAt')
        }
      }, 10000)

      setPollIntervalId(pollInterval)
      
    } catch (err) {
      setError(`❌ Error: ${err.response?.data?.detail || err.message}`)
      setLoading(false)
      localStorage.removeItem('generationProgress')
      localStorage.removeItem('generationStartedAt')
    }
  }

  return (
    <div>
      <h2>✨ Generate New Content</h2>

      <div className="card">
        <div className="card-header">
          <h3>Create AI Video</h3>
        </div>
        <div className="card-content">
          {message && <div className="message message-success">{message}</div>}
          {error && <div className="message message-error">{error}</div>}

          {loading && progress > 0 && (
            <div style={{
              padding: '2rem',
              background: 'linear-gradient(135deg, #2a3a4a 0%, #1f2a3a 100%)',
              borderRadius: '12px',
              marginBottom: '2rem',
              border: '3px solid #667eea',
              boxShadow: '0 0 20px rgba(102, 126, 234, 0.3)'
            }}>
              <div style={{ marginBottom: '1.5rem' }}>
                <p style={{ 
                  fontSize: '1.2rem', 
                  marginBottom: '0.5rem', 
                  fontWeight: 'bold',
                  color: '#fff'
                }}>
                  {progressTitle}
                </p>
              </div>
              <div style={{
                width: '100%',
                height: '12px',
                background: '#0a0a0a',
                borderRadius: '6px',
                overflow: 'hidden',
                marginBottom: '1rem',
                border: '1px solid #444'
              }}>
                <div style={{
                  height: '100%',
                  background: 'linear-gradient(90deg, #667eea 0%, #764ba2 50%, #667eea 100%)',
                  backgroundSize: '200% 100%',
                  width: `${progress}%`,
                  transition: 'width 0.4s ease',
                  borderRadius: '4px',
                  boxShadow: '0 0 10px rgba(102, 126, 234, 0.6)'
                }}></div>
              </div>
              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                marginBottom: '1.5rem'
              }}>
                <p style={{ fontSize: '0.9rem', color: '#aaa' }}>
                  Progress (Stays at {Math.floor(progress)}% until video is complete)
                </p>
                <p style={{ fontSize: '1rem', color: '#667eea', fontWeight: 'bold' }}>
                  {Math.floor(progress)}%
                </p>
              </div>
              <div style={{ 
                fontSize: '0.95rem', 
                color: '#ddd', 
                padding: '1rem',
                background: '#0a0a0a',
                borderRadius: '6px',
                borderLeft: '4px solid #667eea'
              }}>
                <p style={{ margin: 0, marginBottom: '0.5rem' }}>📌 This progress will persist even if you:</p>
                <ul style={{ marginLeft: '1.5rem', marginTop: '0.5rem', marginBottom: '0.5rem' }}>
                  <li>Refresh the page (hard/soft)</li>
                  <li>Switch to other tabs</li>
                  <li>Close and reopen browser</li>
                </ul>
                <p style={{ marginTop: '0.5rem', fontStyle: 'italic', color: '#888', marginBottom: 0 }}>
                  ⏳ Will only complete when video appears in Review tab
                </p>
              </div>
            </div>
          )}

          <div className="form-group">
            <label>📺 Select Channel</label>
            <select
              value={selectedChannel}
              onChange={(e) => setSelectedChannel(e.target.value)}
              disabled={loading}
              style={{
                opacity: loading ? 0.6 : 1,
                cursor: loading ? 'not-allowed' : 'pointer'
              }}
            >
              <option value="">-- Choose Channel --</option>
              {channels.map((ch) => (
                <option key={ch.id} value={ch.id}>
                  {ch.name} ({ch.language.toUpperCase()})
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label>📝 About This Channel</label>
            {channels
              .filter((ch) => ch.id === selectedChannel)
              .map((ch) => (
                <div key={ch.id}>
                  <p><strong>Niche:</strong> {ch.niche}</p>
                  <p><strong>Language:</strong> {ch.language}</p>
                </div>
              ))}
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1.5rem' }}>
            <div className="form-group">
              <label>⏱️ Long Video Duration (minutes)</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <input
                  type="text"
                  inputMode="numeric"
                  value={longDurationInput}
                  onChange={handleLongDurationChange}
                  onBlur={handleLongDurationBlur}
                  disabled={loading}
                  placeholder="15"
                  style={{
                    flex: 1,
                    padding: '0.75rem',
                    background: '#2a2a2a',
                    border: '1px solid #444',
                    color: 'white',
                    borderRadius: '4px',
                    fontSize: '1rem'
                  }}
                />
                <span style={{ 
                  fontSize: '0.9rem', 
                  color: '#999'
                }}>
                  min
                </span>
              </div>
              <p style={{ fontSize: '0.8rem', color: '#999', marginTop: '0.25rem' }}>
                Range: 1-30 minutes
              </p>
            </div>

            <div className="form-group">
              <label>⏱️ Short Video Duration (minutes)</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <input
                  type="text"
                  inputMode="numeric"
                  value={shortDurationInput}
                  onChange={handleShortDurationChange}
                  onBlur={handleShortDurationBlur}
                  disabled={loading}
                  placeholder="1"
                  style={{
                    flex: 1,
                    padding: '0.75rem',
                    background: '#2a2a2a',
                    border: '1px solid #444',
                    color: 'white',
                    borderRadius: '4px',
                    fontSize: '1rem'
                  }}
                />
                <span style={{ 
                  fontSize: '0.9rem', 
                  color: '#999'
                }}>
                  min
                </span>
              </div>
              <p style={{ fontSize: '0.8rem', color: '#999', marginTop: '0.25rem' }}>
                Range: 1-10 minutes (for YouTube Shorts)
              </p>
            </div>
          </div>

          <button
            className="btn btn-primary"
            onClick={handleGenerate}
            disabled={loading || !selectedChannel}
            style={{
              width: '100%',
              padding: '1rem',
              fontSize: '1.1rem',
              fontWeight: 'bold'
            }}
          >
            {loading ? '⏳ Generating...' : '🚀 Generate Content'}
          </button>

          <div style={{ marginTop: '1.5rem', padding: '1rem', background: '#2a2a2a', borderRadius: '8px' }}>
            <p>📄 <strong>What will be created:</strong></p>
            <ul>
              <li>✅ SEO-optimized title, description, tags (via Ollama)</li>
              <li>✅ Long video ({longDuration} minute{longDuration > 1 ? 's' : ''})</li>
              <li>✅ Short video ({shortDuration} minute{shortDuration > 1 ? 's' : ''})</li>
              <li>✅ AI-generated audio narration (Edge-TTS)</li>
              <li>✅ Auto-composed video (FFmpeg)</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
