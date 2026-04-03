import React, { useState, useEffect } from 'react'
import { api } from '../api/client'

export default function Review({ onApproved }) {
  const [videos, setVideos] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedVideo, setSelectedVideo] = useState(null)
  const [videoInfo, setVideoInfo] = useState(null)
  const [editForm, setEditForm] = useState(null)
  const [approving, setApproving] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    loadReviewVideos()
    const interval = setInterval(loadReviewVideos, 5000) // Refresh every 5s
    return () => clearInterval(interval)
  }, [])

  const loadReviewVideos = async () => {
    try {
      const res = await api.listReview()
      setVideos(res.data.videos || [])
      setLoading(false)
    } catch (err) {
      console.error('Failed to load videos', err)
      setLoading(false)
    }
  }

  const selectVideo = async (video) => {
    setSelectedVideo(video)
    setVideoInfo(null)
    setEditForm(null)
    setMessage('')
    setError('')

    try {
      const res = await api.getVideoInfo(video.job_id)
      setVideoInfo(res.data)
      setEditForm({
        title: res.data.metadata.title || '',
        description: res.data.metadata.description || '',
        tags: res.data.metadata.tags || '',
      })
    } catch (err) {
      setError('Failed to load video info')
    }
  }

  const handleApprove = async () => {
    if (!selectedVideo || !editForm) return

    setApproving(true)
    setError('')
    setMessage('')

    try {
      await api.approveVideo(
        selectedVideo.job_id,
        editForm.title,
        editForm.description,
        editForm.tags
      )
      setMessage('✅ Video approved and queued for upload!')
      setTimeout(() => {
        loadReviewVideos()
        setSelectedVideo(null)
        setVideoInfo(null)
        onApproved()
      }, 2000)
    } catch (err) {
      setError(`❌ Error: ${err.response?.data?.detail || err.message}`)
    } finally {
      setApproving(false)
    }
  }

  if (loading) {
    return (
      <div>
        <h2>👁️ Review Videos</h2>
        <div className="loading">
          <div className="spinner"></div>
        </div>
      </div>
    )
  }

  if (videos.length === 0) {
    return (
      <div>
        <h2>👁️ Review Videos</h2>
        <div className="card">
          <div style={{ padding: '2rem', textAlign: 'center' }}>
            <p style={{ fontSize: '1.1rem', marginBottom: '1rem' }}>📹 No videos ready for review yet</p>
            <p style={{ color: '#999', marginBottom: '1rem' }}>
              Videos are still being generated. This can take 5-15 minutes depending on model speed.
            </p>
            <div className="spinner" style={{ margin: '1rem auto' }}></div>
            <p style={{ fontSize: '0.9rem', color: '#666', marginTop: '1rem' }}>
              💡 Tip: This page auto-refreshes every 5 seconds. Videos will appear here when ready.
            </p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div>
      <h2>👁️ Review Videos ({videos.length})</h2>

      <div className="grid grid-2">
        {/* Video List */}
        <div>
          <div className="card">
            <div className="card-header">
              <h3>📹 Videos</h3>
            </div>
            <div className="card-content">
              {videos.map((video) => (
                <div
                  key={video.job_id}
                  className="card"
                  onClick={() => selectVideo(video)}
                  style={{
                    cursor: 'pointer',
                    background: selectedVideo?.job_id === video.job_id ? '#333' : '#1a1a1a',
                    borderColor: selectedVideo?.job_id === video.job_id ? '#667eea' : '#333',
                  }}
                >
                  <p><strong>📺 {video.channel}</strong></p>
                  <p style={{ fontSize: '0.9rem', color: '#999' }}>
                    Created: {video.created_at || 'N/A'}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Video Details & Edit */}
        <div>
          {selectedVideo && videoInfo ? (
            <>
              <div className="card">
                <div className="card-header">
                  <h3>🎬 Preview</h3>
                </div>
                <div className="card-content">
                  {videoInfo.media_files.length > 0 ? (
                    <div style={{ marginBottom: '1rem' }}>
                      <video
                        width="100%"
                        height="auto"
                        controls
                        style={{ 
                          borderRadius: '8px',
                          background: '#000',
                          minHeight: '300px'
                        }}
                      >
                        <source
                          src={api.getVideoFile(selectedVideo.job_id, 'long.mp4')}
                          type="video/mp4"
                        />
                        Your browser does not support video playback.
                      </video>
                      <p style={{ fontSize: '0.85rem', color: '#999', marginTop: '0.5rem' }}>
                        ✅ Video available for preview (long.mp4)
                      </p>
                    </div>
                  ) : (
                    <div style={{ 
                      padding: '2rem', 
                      textAlign: 'center', 
                      background: '#2a2a2a',
                      borderRadius: '8px',
                      color: '#999'
                    }}>
                      ⏳ Video is being processed. Please wait...
                    </div>
                  )}
                </div>
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>📝 Script Preview</h3>
                </div>
                <div className="card-content">
                  <div style={{
                    background: '#2a2a2a',
                    padding: '1rem',
                    borderRadius: '8px',
                    maxHeight: '200px',
                    overflowY: 'auto',
                    fontSize: '0.9rem',
                    lineHeight: '1.6'
                  }}>
                    {videoInfo.metadata.script_long ? (
                      <p>{videoInfo.metadata.script_long}</p>
                    ) : (
                      <p style={{ color: '#666' }}>No script available yet</p>
                    )}
                  </div>
                </div>
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>✏️ Edit Metadata</h3>
                </div>
                <div className="card-content">
                  {message && <div className="message message-success">{message}</div>}
                  {error && <div className="message message-error">{error}</div>}

                  <div className="form-group">
                    <label>🎬 Title</label>
                    <input
                      type="text"
                      value={editForm.title}
                      onChange={(e) => setEditForm({ ...editForm, title: e.target.value })}
                      placeholder="Video title"
                    />
                  </div>

                  <div className="form-group">
                    <label>📝 Description</label>
                    <textarea
                      value={editForm.description}
                      onChange={(e) => setEditForm({ ...editForm, description: e.target.value })}
                      placeholder="Video description"
                    />
                  </div>

                  <div className="form-group">
                    <label>🏷️ Tags (comma separated)</label>
                    <input
                      type="text"
                      value={editForm.tags}
                      onChange={(e) => setEditForm({ ...editForm, tags: e.target.value })}
                      placeholder="tag1, tag2, tag3"
                    />
                  </div>

                  <button
                    className="btn btn-success"
                    onClick={handleApprove}
                    disabled={approving}
                  >
                    {approving ? '⏳ Approving...' : '✅ Approve & Queue'}
                  </button>
                </div>
              </div>
            </>
          ) : (
            <div className="card">
              <p>Select a video from the list to preview and edit</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
