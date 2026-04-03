import React, { useState, useEffect } from 'react'
import './styles.css'
import Dashboard from './pages/Dashboard'
import Generate from './pages/Generate'
import Review from './pages/Review'
import Queue from './pages/Queue'
import YouTubeStudio from './pages/YouTubeStudio'
import Automation from './pages/Automation'
import { api } from './api/client'

export default function App() {
  const [currentPage, setCurrentPage] = useState(() => {
    return localStorage.getItem('activePage') || 'dashboard'
  })
  const [status, setStatus] = useState(null)
  const [loading, setLoading] = useState(true)

  const navigateTo = (page) => {
    localStorage.setItem('activePage', page)
    setCurrentPage(page)
  }

  useEffect(() => {
    loadStatus()
    const interval = setInterval(loadStatus, 5000) // Refresh every 5s
    return () => clearInterval(interval)
  }, [])

  const loadStatus = async () => {
    try {
      const res = await api.getStatus()
      setStatus(res.data.counts)
      setLoading(false)
    } catch (err) {
      console.error('Status error:', err)
    }
  }

  return (
    <div className="app">
      {/* Header */}
      <header className="header">
        <div className="header-content">
          <h1>🎬 YouTube AI Agent</h1>
          <p>Automated content generation, review & upload</p>
        </div>
      </header>

      {/* Navigation */}
      <nav className="navbar">
        <button
          className={`nav-btn ${currentPage === 'dashboard' ? 'active' : ''}`}
          onClick={() => navigateTo('dashboard')}
        >
          📊 Dashboard
        </button>
        <button
          className={`nav-btn ${currentPage === 'generate' ? 'active' : ''}`}
          onClick={() => navigateTo('generate')}
        >
          ✨ Generate
        </button>
        <button
          className={`nav-btn ${currentPage === 'review' ? 'active' : ''}`}
          onClick={() => navigateTo('review')}
        >
          👁️ Review ({status?.ready_for_review || 0})
        </button>
        <button
          className={`nav-btn ${currentPage === 'queue' ? 'active' : ''}`}
          onClick={() => navigateTo('queue')}
        >
          📤 Queue ({status?.pending_upload || 0})
        </button>
        <button
          className={`nav-btn ${currentPage === 'automation' ? 'active' : ''}`}
          onClick={() => navigateTo('automation')}
          style={{ borderLeft: '2px solid #4caf50' }}
        >
          🤖 Automation
        </button>
        <button
          className={`nav-btn ${currentPage === 'workflow' ? 'active' : ''}`}
          onClick={() => navigateTo('workflow')}
          style={{ borderLeft: '2px solid #ff6d00' }}
        >
          ⚙️ Workflow
        </button>
        <button
          className={`nav-btn ${currentPage === 'studio-en' ? 'active' : ''}`}
          onClick={() => navigateTo('studio-en')}
          style={{ borderLeft: '2px solid #ff4444' }}
        >
          🇬🇧 EN Studio
        </button>
        <button
          className={`nav-btn ${currentPage === 'studio-te' ? 'active' : ''}`}
          onClick={() => navigateTo('studio-te')}
          style={{ borderLeft: '2px solid #ff9900' }}
        >
          🇮🇳 TE Studio
        </button>
      </nav>

      {/* Main Content */}
      <main className="main-content">
        {currentPage === 'dashboard' && <Dashboard status={status} />}
        {currentPage === 'generate' && <Generate onGenerated={() => { loadStatus(); navigateTo('review') }} />}
        {currentPage === 'review' && <Review onApproved={() => loadStatus()} />}
        {currentPage === 'queue' && <Queue />}
        {currentPage === 'automation' && <Automation />}
        {currentPage === 'workflow' && (
          <div>
            <h2>⚙️ n8n Workflow Engine</h2>
            <div className="card" style={{ marginBottom: '1.5rem', border: '1px solid #ff6d0044' }}>
              <div className="card-header" style={{ borderLeft: '4px solid #ff6d00' }}>
                <h3>🔗 Open n8n</h3>
              </div>
              <div className="card-content">
                <p style={{ color: '#aaa', marginBottom: '1rem' }}>
                  n8n is your workflow automation engine. It handles scheduled uploads, webhook triggers, and integrations.
                  n8n blocks iframe embedding for security, so it opens in a separate tab.
                </p>
                <button
                  onClick={() => window.open('http://localhost:5678', '_blank', 'noopener,noreferrer')}
                  style={{ width: '100%', padding: '1.2rem', fontSize: '1.2rem', fontWeight: 'bold', background: 'linear-gradient(135deg, #ff6d00, #ff9100)', color: 'white', border: 'none', borderRadius: '8px', cursor: 'pointer', marginBottom: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.75rem' }}
                >
                  <span style={{ fontSize: '1.5rem' }}>⚙️</span>
                  Open n8n Workflow Editor
                  <span style={{ fontSize: '0.85rem', opacity: 0.85 }}>(opens in new tab)</span>
                </button>
              </div>
            </div>
            <div className="card" style={{ border: '1px solid #333' }}>
              <div className="card-header">
                <h3>📋 Quick Links</h3>
              </div>
              <div className="card-content">
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '0.75rem' }}>
                  {[
                    { label: '📊 Workflows', url: 'http://localhost:5678/workflows' },
                    { label: '▶️ Executions', url: 'http://localhost:5678/executions' },
                    { label: '🔑 Credentials', url: 'http://localhost:5678/credentials' },
                  ].map(link => (
                    <button
                      key={link.label}
                      onClick={() => window.open(link.url, '_blank', 'noopener,noreferrer')}
                      style={{ padding: '0.8rem', background: '#1a1a2e', color: '#ccc', border: '1px solid #333', borderRadius: '6px', cursor: 'pointer', fontSize: '0.95rem', textAlign: 'center' }}
                    >
                      {link.label}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}
        {currentPage === 'studio-en' && <YouTubeStudio channel="edgeviralhub" />}
        {currentPage === 'studio-te' && <YouTubeStudio channel="manatelugodu" />}
      </main>

      {/* Footer */}
      <footer className="footer">
        <p>🤖 Powered by Ollama | 🔊 Edge-TTS | 🎥 FFmpeg | 📡 n8n</p>
      </footer>
    </div>
  )
}
