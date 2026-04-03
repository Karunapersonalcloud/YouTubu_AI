import React from 'react'
import { api } from '../api/client'

export default function Dashboard({ status }) {
  return (
    <div>
      <h2>📊 Dashboard</h2>
      
      {status ? (
        <>
          <div className="stats-grid">
            <div className="stat-card">
              <div className="number">{status.ready_for_review || 0}</div>
              <div className="label">Ready for Review</div>
            </div>
            <div className="stat-card">
              <div className="number">{status.approved || 0}</div>
              <div className="label">Approved</div>
            </div>
            <div className="stat-card">
              <div className="number">{status.pending_upload || 0}</div>
              <div className="label">Pending Upload</div>
            </div>
            <div className="stat-card">
              <div className="number">{status.uploaded || 0}</div>
              <div className="label">Uploaded</div>
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>📈 Workflow Stages</h3>
            </div>
            <div className="card-content">
              <p>
                <strong>1. Generate</strong> → Create new content with AI<br/>
                <strong>2. Review</strong> → Watch and edit videos<br/>
                <strong>3. Approve</strong> → Queue for upload<br/>
                <strong>4. Upload</strong> → n8n automation handles YouTube publishing
              </p>
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>⚡ Quick Tips</h3>
            </div>
            <div className="card-content">
              <ul>
                <li>🎯 Generate content for EN or TE channels</li>
                <li>👁️ Review videos before approval</li>
                <li>📝 Edit title, description, tags before upload</li>
                <li>🔄 Check Queue page to see pending uploads</li>
                <li>📱 Mobile-friendly interface</li>
              </ul>
            </div>
          </div>
        </>
      ) : (
        <div className="loading">
          <div className="spinner"></div>
          <p>Loading...</p>
        </div>
      )}
    </div>
  )
}
