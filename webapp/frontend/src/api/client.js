import axios from 'axios'

const API_BASE = 'http://localhost:8000/api'

export const api = {
  // Channels
  getChannels: () => axios.get(`${API_BASE}/channels`),
  
  // Generation
  generateContent: (channel, longDuration = 15, shortDuration = 1) => 
    axios.post(`${API_BASE}/generate`, { channel, long_duration: longDuration, short_duration: shortDuration }),
  
  // Video Lists
  listReview: () => axios.get(`${API_BASE}/videos/review`),
  listApproved: () => axios.get(`${API_BASE}/videos/approved`),
  listUploaded: () => axios.get(`${API_BASE}/videos/uploaded`),
  listQueue: () => axios.get(`${API_BASE}/videos/queue`),
  
  // Video Details
  getVideoInfo: (jobId) => axios.get(`${API_BASE}/videos/${jobId}/info`),
  getVideoFile: (jobId, filename) => `${API_BASE}/videos/${jobId}/video/${filename}`,
  
  // Actions
  approveVideo: (jobId, title, description, tags) =>
    axios.post(`${API_BASE}/videos/${jobId}/approve`, {
      job_id: jobId,
      edited_title: title,
      edited_description: description,
      edited_tags: tags,
    }),
  
  editVideoMetadata: (jobId, title, description, tags) =>
    axios.post(`${API_BASE}/videos/${jobId}/edit`, { title, description, tags }),
  
  // Queue & Upload
  getSeoMetadata: (jobId) => axios.get(`${API_BASE}/queue/${jobId}/seo-metadata`),
  uploadNow: (jobId, title, description, tags) =>
    axios.post(`${API_BASE}/queue/${jobId}/upload-now`, { title, description, tags }),

  // Automation & YouTube Upload
  getAutomationStatus: () => axios.get(`${API_BASE}/automation/status`),
  oauthSetup: (channel, clientId, clientSecret) =>
    axios.post(`${API_BASE}/automation/oauth/setup`, { channel, client_id: clientId, client_secret: clientSecret }),
  oauthDisconnect: (channel) => axios.delete(`${API_BASE}/automation/oauth/${channel}`),
  reviewContent: (jobId) => axios.get(`${API_BASE}/automation/review/${jobId}`),
  uploadToYouTube: (jobId) => axios.post(`${API_BASE}/automation/upload/${jobId}`),
  removeFromQueue: (jobId) => axios.post(`${API_BASE}/automation/queue/${jobId}/remove`),
  autoPublish: (jobId) => axios.post(`${API_BASE}/automation/auto-publish/${jobId}`),
  autoPublishAll: () => axios.post(`${API_BASE}/automation/auto-publish-all`),
  forceUpload: (jobId) => axios.post(`${API_BASE}/automation/force-upload/${jobId}`),

  // Status
  getStatus: () => axios.get(`${API_BASE}/status`),
}
