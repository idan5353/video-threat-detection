import React, { useState } from 'react';


const VideoPlayer = ({ videoUrl, videoName, analysisResults }) => {
  const [currentTime, setCurrentTime] = useState(0);

  const handleTimeUpdate = (e) => {
    setCurrentTime(e.target.currentTime);
  };

  const threats = analysisResults.flatMap(result => result.threats || []);
  const currentThreats = threats.filter(threat => 
    Math.abs((threat.timestamp / 1000) - currentTime) < 2
  );

  return (
    <div className="video-player">
      <h3>🎬 {videoName}</h3>
      
      <div style={{ position: 'relative' }}>
        <video
          controls
          style={{ width: '100%', maxHeight: '400px' }}
          onTimeUpdate={handleTimeUpdate}
          crossOrigin="anonymous"
        >
          <source src={videoUrl} type="video/mp4" />
          Your browser does not support the video tag.
        </video>
        
        {currentThreats.length > 0 && (
          <div style={{
            position: 'absolute',
            top: '10px',
            left: '10px',
            background: 'rgba(255, 0, 0, 0.8)',
            color: 'white',
            padding: '10px',
            borderRadius: '5px'
          }}>
            ⚠️ {currentThreats.length} threat(s) detected at this time
          </div>
        )}
      </div>
      
      {threats.length > 0 && (
        <div style={{ marginTop: '20px' }}>
          <h4>🎯 Detected Threats Timeline</h4>
          <div style={{ maxHeight: '200px', overflowY: 'auto' }}>
            {threats.map((threat, index) => (
              <div 
                key={index}
                style={{
                  padding: '10px',
                  margin: '5px 0',
                  border: '1px solid #ddd',
                  borderRadius: '5px',
                  backgroundColor: '#f8f9fa'
                }}
              >
                <strong>{threat.label}</strong> - {Math.round(threat.confidence)}% confidence
                <br />
                <small>At {Math.floor(threat.timestamp / 1000)}s</small>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default VideoPlayer;
