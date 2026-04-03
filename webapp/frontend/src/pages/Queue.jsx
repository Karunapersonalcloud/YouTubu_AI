import React, { useState, useEffect } from 'react'
import { api } from '../api/client'

export default function Queue() {
  const [queueVideos, setQueueVideos] = useState([])
  const [approvedVideos, setApprovedVideos] = useState([])
  const [uploadedVideos, setUploadedVideos] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('pending')
  const [showMetadataModal, setShowMetadataModal] = useState(false)
  const [selectedVideo, setSelectedVideo] = useState(null)
  const [generatedMetadata, setGeneratedMetadata] = useState(null)
  const [metadataLoading, setMetadataLoading] = useState(false)
  const [editedMetadata, setEditedMetadata] = useState({
    title: '',
    description: '',
    tags: ''
  })
  const [uploadingVideo, setUploadingVideo] = useState(null)

  useEffect(() => {
    loadAllQueues()
    const interval = setInterval(loadAllQueues, 10000)
    return () => clearInterval(interval)
  }, [])

  const loadAllQueues = async () => {
    try {
      const [queue, approved, uploaded] = await Promise.all([
        api.listQueue(),
        api.listApproved(),
        api.listUploaded(),
      ])
      setQueueVideos(queue.data.videos || [])
      setApprovedVideos(approved.data.videos || [])
      setUploadedVideos(uploaded.data.videos || [])
      setLoading(false)
    } catch (err) {
      console.error('Failed to load queues', err)
      setLoading(false)
    }
  }

  const handleViewMetadata = async (video) => {
    setSelectedVideo(video)
    setShowMetadataModal(true)
    setMetadataLoading(true)
    setEditedMetadata({
      title: video.title || '',
      description: video.description || '',
      tags: video.tags || ''
    })
    
    try {
      const response = await api.getSeoMetadata(video.job_id)
      setGeneratedMetadata(response.data.generated_metadata)
      // Pre-fill with generated metadata if empty
      if (!video.title) {
        setEditedMetadata(prev => ({
          ...prev,
          title: response.data.generated_metadata.title
        }))
      }
      if (!video.description) {
        setEditedMetadata(prev => ({
          ...prev,
          description: response.data.generated_metadata.description
        }))
      }
      if (!video.tags) {
        setEditedMetadata(prev => ({
          ...prev,
          tags: response.data.generated_metadata.tags
        }))
      }
    } catch (err) {
      console.error('Failed to generate SEO metadata', err)
    }
    setMetadataLoading(false)
  }

  const handleUploadNow = async () => {
    if (!selectedVideo) return
    
    setUploadingVideo(selectedVideo.job_id)
    try {
      await api.uploadNow(selectedVideo.job_id, editedMetadata.title, editedMetadata.description, editedMetadata.tags)
      setShowMetadataModal(false)
      setSelectedVideo(null)
      await loadAllQueues()
    } catch (err) {
      console.error('Failed to trigger upload', err)
      alert('Error: ' + err.message)
    }
    setUploadingVideo(null)
  }

  if (loading) {
    return (
      <div>
        <h2>📤 Upload Queue</h2>
        <div className="loading">
          <div className="spinner"></div>
        </div>
      </div>
    )
  }

  return (
    <div>
      <h2>📤 Upload Queue & History</h2>

      {/* Tabs */}
      <div className="navbar" style={{ marginBottom: '2rem' }}>
        <button
          className={`nav-btn ${activeTab === 'pending' ? 'active' : ''}`}
          onClick={() => setActiveTab('pending')}
        >
          ⏳ Pending ({queueVideos.length})
        </button>
        <button
          className={`nav-btn ${activeTab === 'approved' ? 'active' : ''}`}
          onClick={() => setActiveTab('approved')}
        >
          ✅ Approved ({approvedVideos.length})
        </button>
        <button
          className={`nav-btn ${activeTab === 'uploaded' ? 'active' : ''}`}
          onClick={() => setActiveTab('uploaded')}
        >
          🎬 Uploaded ({uploadedVideos.length})
        </button>
      </div>

      {activeTab === 'pending' && (
        <>
          {queueVideos.length === 0 ? (
            <div className="card">
              <p>No videos pending upload. Approve videos from the Review page.</p>
            </div>
          ) : (
            <div className="grid grid-2">
              {queueVideos.map((video) => (
                <div key={video.job_id} className="card">
                  <h3>🎬 {video.channel}</h3>
                  <p><strong>Job:</strong> {video.job_id}</p>
                  <p><strong>Title:</strong> {video.title || 'N/A'}</p>
                  <p><strong>Status:</strong> <span className="badge badge-warning">Pending Upload</span></p>
                  <p style={{ fontSize: '0.9rem', color: '#999', marginBottom: '1rem' }}>
                    Approved: {video.approved_at ? new Date(video.approved_at).toLocaleString() : 'N/A'}
                  </p>
                  <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                    <button
                      onClick={() => handleViewMetadata(video)}
                      style={{
                        padding: '0.6rem 1rem',
                        background: '#667eea',
                        color: 'white',
                        border: 'none',
                        borderRadius: '4px',
                        cursor: 'pointer',
                        fontSize: '0.9rem'
                      }}
                    >
                      ✏️ View & Edit
                    </button>
                    <button
                      onClick={() => {
                        setEditedMetadata({
                          title: video.title || '',
                          description: video.description || '',
                          tags: video.tags || ''
                        })
                        setSelectedVideo(video)
                        setGeneratedMetadata(null)
                        setShowMetadataModal(true)
                      }}
                      style={{
                        padding: '0.6rem 1rem',
                        background: '#48bb78',
                        color: 'white',
                        border: 'none',
                        borderRadius: '4px',
                        cursor: 'pointer',
                        fontSize: '0.9rem'
                      }}
                    >
                      🚀 Upload Now
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {activeTab === 'approved' && (
        <>
          {approvedVideos.length === 0 ? (
            <div className="card">
              <p>No approved videos. Review and approve videos to see them here.</p>
            </div>
          ) : (
            <div className="grid grid-2">
              {approvedVideos.map((video) => (
                <div key={video.job_id} className="card">
                  <h3>🎬 {video.channel}</h3>
                  <p><strong>Job:</strong> {video.job_id}</p>
                  <p><strong>Created:</strong> {video.created_at || 'N/A'}</p>
                  <p><strong>Status:</strong> <span className="badge badge-info">Approved</span></p>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {activeTab === 'uploaded' && (
        <>
          {uploadedVideos.length === 0 ? (
            <div className="card">
              <p>No uploaded videos yet. Pending videos will appear here after upload.</p>
            </div>
          ) : (
            <div className="grid grid-2">
              {uploadedVideos.map((video) => (
                <div key={video.job_id} className="card">
                  <h3>🎬 {video.channel}</h3>
                  <p><strong>Job:</strong> {video.job_id}</p>
                  <p><strong>Status:</strong> <span className="badge badge-success">✅ Uploaded</span></p>
                  <p style={{ fontSize: '0.9rem', color: '#999' }}>
                    Channel: <strong>{video.channel}</strong>
                  </p>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      <div className="card" style={{ marginTop: '2rem' }}>
        <div className="card-header">
          <h3>ℹ️ How It Works</h3>
        </div>
        <div className="card-content">
          <ol>
            <li><strong>Generate</strong> new content → moves to Review</li>
            <li><strong>Review & Edit</strong> metadata → approve video</li>
            <li><strong>Approved videos</strong> → View & Edit SEO metadata</li>
            <li><strong>Upload Now</strong> or let n8n schedule it automatically</li>
            <li><strong>YouTube API</strong> uploads with metadata (title, description, tags)</li>
            <li><strong>Finished</strong> → moved to Uploaded</li>
          </ol>
          <p style={{ marginTop: '1rem', padding: '1rem', background: '#2a2a2a', borderRadius: '8px' }}>
            📡 <strong>n8n is running in Docker</strong> and polls the upload queue.<br/>
            💾 To restart: <code>docker-compose down && docker-compose up -d</code>
          </p>
        </div>
      </div>

      {/* Metadata Modal */}
      {showMetadataModal && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0,0,0,0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000
        }}>
          <div style={{
            background: '#1a1a1a',
            borderRadius: '8px',
            padding: '2rem',
            maxWidth: '600px',
            width: '90%',
            maxHeight: '80vh',
            overflowY: 'auto',
            border: '2px solid #667eea'
          }}>
            <h2 style={{ marginBottom: '1.5rem' }}>🎬 {selectedVideo?.channel} - Upload Metadata</h2>

            {metadataLoading ? (
              <div style={{ textAlign: 'center', padding: '2rem' }}>
                <div className="spinner"></div>
                <p style={{ marginTop: '1rem', color: '#999' }}>Generating SEO metadata...</p>
              </div>
            ) : (
              <>
                {generatedMetadata && (
                  <div style={{
                    background: '#2a2a2a',
                    padding: '1rem',
                    borderRadius: '6px',
                    marginBottom: '1.5rem',
                    border: '1px solid #444'
                  }}>
                    <p style={{ fontSize: '0.85rem', color: '#999', marginBottom: '0.5rem' }}>💡 Auto-Generated Suggestions:</p>
                    <p><strong>Title:</strong> {generatedMetadata.title}</p>
                    <p><strong>Description:</strong> {generatedMetadata.description}</p>
                    <p><strong>Tags:</strong> {generatedMetadata.tags}</p>
                  </div>
                )}

                <div style={{ marginBottom: '1rem' }}>
                  <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.95rem' }}>
                    <strong>📝 Title</strong> (max 60 chars)
                  </label>
                  <input
                    type="text"
                    value={editedMetadata.title}
                    onChange={(e) => setEditedMetadata(prev => ({
                      ...prev,
                      title: e.target.value.slice(0, 60)
                    }))}
                    style={{
                      width: '100%',
                      padding: '0.75rem',
                      background: '#2a2a2a',
                      border: '1px solid #444',
                      color: 'white',
                      borderRadius: '4px',
                      fontSize: '0.95rem',
                      boxSizing: 'border-box'
                    }}
                  />
                  <p style={{ fontSize: '0.8rem', color: '#999', marginTop: '0.25rem' }}>
                    {editedMetadata.title.length}/60
                  </p>
                </div>

                <div style={{ marginBottom: '1rem' }}>
                  <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.95rem' }}>
                    <strong>📄 Description</strong> (max 200 chars)
                  </label>
                  <textarea
                    value={editedMetadata.description}
                    onChange={(e) => setEditedMetadata(prev => ({
                      ...prev,
                      description: e.target.value.slice(0, 200)
                    }))}
                    rows="4"
                    style={{
                      width: '100%',
                      padding: '0.75rem',
                      background: '#2a2a2a',
                      border: '1px solid #444',
                      color: 'white',
                      borderRadius: '4px',
                      fontSize: '0.95rem',
                      boxSizing: 'border-box',
                      fontFamily: 'inherit'
                    }}
                  />
                  <p style={{ fontSize: '0.8rem', color: '#999', marginTop: '0.25rem' }}>
                    {editedMetadata.description.length}/200
                  </p>
                </div>

                <div style={{ marginBottom: '1.5rem' }}>
                  <label style={{ display: 'block', marginBottom: '0.5rem', fontSize: '0.95rem' }}>
                    <strong>🏷️ Tags</strong> (comma-separated)
                  </label>
                  <input
                    type="text"
                    value={editedMetadata.tags}
                    onChange={(e) => setEditedMetadata(prev => ({
                      ...prev,
                      tags: e.target.value
                    }))}
                    placeholder="AI, video, content, trending"
                    style={{
                      width: '100%',
                      padding: '0.75rem',
                      background: '#2a2a2a',
                      border: '1px solid #444',
                      color: 'white',
                      borderRadius: '4px',
                      fontSize: '0.95rem',
                      boxSizing: 'border-box'
                    }}
                  />
                </div>

                <div style={{ display: 'flex', gap: '1rem' }}>
                  <button
                    onClick={handleUploadNow}
                    disabled={uploadingVideo === selectedVideo?.job_id}
                    style={{
                      flex: 1,
                      padding: '0.75rem',
                      background: uploadingVideo === selectedVideo?.job_id ? '#666' : '#48bb78',
                      color: 'white',
                      border: 'none',
                      borderRadius: '4px',
                      cursor: uploadingVideo === selectedVideo?.job_id ? 'not-allowed' : 'pointer',
                      fontSize: '1rem',
                      fontWeight: 'bold'
                    }}
                  >
                    {uploadingVideo === selectedVideo?.job_id ? '⏳ Uploading...' : '🚀 Upload Now'}
                  </button>
                  <button
                    onClick={() => setShowMetadataModal(false)}
                    style={{
                      flex: 1,
                      padding: '0.75rem',
                      background: '#666',
                      color: 'white',
                      border: 'none',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      fontSize: '1rem'
                    }}
                  >
                    ✕ Cancel
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
