import React, { useState, useEffect, useRef } from 'react';
import VideoUpload from './components/VideoUpload';
import VideoPlayer from './components/VideoPlayer';
import ThreatDashboard from './components/ThreatDashboard';
import WebSocketManager from './services/WebSocketManager';
import './App.css';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'https://rgwh1nruq7.execute-api.us-west-2.amazonaws.com/prod';
const WS_URL = process.env.REACT_APP_WEBSOCKET_URL || 'wss://ufdrenitih.execute-api.us-west-2.amazonaws.com/prod';

function App() {
  const [uploadedVideo, setUploadedVideo] = useState(null);
  const [analysisResults, setAnalysisResults] = useState([]);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState('disconnected');
  const [notifications, setNotifications] = useState([]);
  const wsManagerRef = useRef(null);

  useEffect(() => {
    // Initialize WebSocket connection
    wsManagerRef.current = new WebSocketManager(WS_URL);
    
    wsManagerRef.current.onConnectionChange = (status) => {
      setConnectionStatus(status);
    };

    wsManagerRef.current.onThreatDetected = (threatData) => {
      console.log('Threat detected:', threatData);
      setAnalysisResults(prev => [...prev, threatData]);
      
      // Add notification
      const notification = {
        id: Date.now(),
        type: 'threat',
        message: `🚨 ${threatData.threat_count} threat(s) detected in video`,
        timestamp: new Date().toLocaleTimeString(),
        data: threatData
      };
      setNotifications(prev => [notification, ...prev.slice(0, 9)]);
    };

    wsManagerRef.current.onProcessingUpdate = (updateData) => {
      console.log('Processing update:', updateData);
      
      if (updateData.status === 'PROCESSING_STARTED') {
        setIsAnalyzing(true);
        const notification = {
          id: Date.now(),
          type: 'info',
          message: '🔄 Video analysis started',
          timestamp: new Date().toLocaleTimeString()
        };
        setNotifications(prev => [notification, ...prev.slice(0, 9)]);
      } else if (updateData.status === 'PROCESSING_COMPLETE') {
        setIsAnalyzing(false);
        const notification = {
          id: Date.now(),
          type: 'success',
          message: '✅ Video analysis complete',
          timestamp: new Date().toLocaleTimeString()
        };
        setNotifications(prev => [notification, ...prev.slice(0, 9)]);
      }
    };

    wsManagerRef.current.connect();

    return () => {
      if (wsManagerRef.current) {
        wsManagerRef.current.disconnect();
      }
    };
  }, []);

  const handleVideoUploaded = (videoData) => {
    setUploadedVideo(videoData);
    setAnalysisResults([]);
    setIsAnalyzing(true);
    
    const notification = {
      id: Date.now(),
      type: 'info',
      message: `📹 Video "${videoData.name}" uploaded successfully`,
      timestamp: new Date().toLocaleTimeString()
    };
    setNotifications(prev => [notification, ...prev.slice(0, 9)]);
  };

  const clearResults = () => {
    setAnalysisResults([]);
    setUploadedVideo(null);
    setIsAnalyzing(false);
    setNotifications([]);
  };

  return (
    <div className="App">
      <header className="app-header">
        <div className="header-content">
          <h1>🎥 Video Threat Detection System</h1>
          <div className="connection-status">
            <span className={`status-indicator ${connectionStatus}`}></span>
            <span className="status-text">
              {connectionStatus === 'connected' ? 'Live' : 'Offline'}
            </span>
          </div>
        </div>
      </header>

      <main className="app-main">
        <div className="app-layout">
          {/* Left Panel - Upload and Video Player */}
          <div className="left-panel">
            <div className="upload-section">
              <VideoUpload 
                apiUrl={API_BASE_URL}
                onVideoUploaded={handleVideoUploaded}
                isAnalyzing={isAnalyzing}
              />
            </div>

            {uploadedVideo && (
              <div className="video-section">
                <VideoPlayer
                  videoUrl={uploadedVideo.url}
                  videoName={uploadedVideo.name}
                  analysisResults={analysisResults}
                />
              </div>
            )}
          </div>

          {/* Right Panel - Dashboard and Notifications */}
          <div className="right-panel">
            <div className="dashboard-section">
              <ThreatDashboard
                analysisResults={analysisResults}
                isAnalyzing={isAnalyzing}
                onClearResults={clearResults}
              />
            </div>

            <div className="notifications-section">
              <h3>🔔 Live Notifications</h3>
              <div className="notifications-list">
                {notifications.length === 0 ? (
                  <div className="no-notifications">
                    No notifications yet. Upload a video to start analysis.
                  </div>
                ) : (
                  notifications.map(notification => (
                    <div 
                      key={notification.id} 
                      className={`notification ${notification.type}`}
                    >
                      <div className="notification-message">
                        {notification.message}
                      </div>
                      <div className="notification-time">
                        {notification.timestamp}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;
