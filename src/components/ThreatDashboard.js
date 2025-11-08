import React from 'react';


const ThreatDashboard = ({ analysisResults, isAnalyzing, onClearResults }) => {
  const threats = analysisResults.flatMap(result => result.threats || []);
  const totalThreats = threats.length;
  const uniqueTypes = [...new Set(threats.map(t => t.type))].length;
  const avgConfidence = threats.length > 0 
    ? Math.round(threats.reduce((sum, t) => sum + t.confidence, 0) / threats.length)
    : 0;

  if (isAnalyzing) {
    return (
      <div style={{ textAlign: 'center', padding: '20px' }}>
        <h2>🔍 Analysis Dashboard</h2>
        <div style={{ margin: '20px 0' }}>
          <div style={{ 
            width: '40px',
            height: '40px',
            border: '4px solid #f3f3f3',
            borderTop: '4px solid #3498db',
            borderRadius: '50%',
            animation: 'spin 2s linear infinite',
            margin: '0 auto 1rem'
          }} />
          <p>Analyzing video for potential threats...</p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', marginTop: '1rem' }}>
            <span style={{ padding: '0.25rem 0.5rem', backgroundColor: 'rgba(59, 130, 246, 0.3)', borderRadius: '4px', fontSize: '0.75rem' }}>
              Object Detection
            </span>
            <span style={{ padding: '0.25rem 0.5rem', backgroundColor: 'rgba(59, 130, 246, 0.3)', borderRadius: '4px', fontSize: '0.75rem' }}>
              Content Moderation
            </span>
            <span style={{ padding: '0.25rem 0.5rem', backgroundColor: 'rgba(59, 130, 246, 0.3)', borderRadius: '4px', fontSize: '0.75rem' }}>
              Person Tracking
            </span>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <h2>🔍 Analysis Dashboard</h2>
        {analysisResults.length > 0 && (
          <button onClick={onClearResults} style={{ 
            padding: '0.5rem 1rem',
            backgroundColor: '#ef4444',
            color: 'white',
            border: 'none',
            borderRadius: '6px',
            cursor: 'pointer',
            fontSize: '0.875rem'
          }}>
            🗑️ Clear Results
          </button>
        )}
      </div>

      {analysisResults.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '40px' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>🛡️</div>
          <p>No analysis results yet</p>
          <span style={{ color: '#64748b' }}>Upload a video to start threat detection</span>
        </div>
      ) : (
        <div>
          {/* Summary Stats */}
          <div style={{ 
            display: 'grid', 
            gridTemplateColumns: 'repeat(3, 1fr)', 
            gap: '15px',
            marginBottom: '20px'
          }}>
            <div style={{ 
              background: 'rgba(51, 65, 85, 0.5)', 
              padding: '15px', 
              borderRadius: '8px', 
              textAlign: 'center',
              border: '1px solid rgba(239, 68, 68, 0.3)'
            }}>
              <div style={{ fontSize: '2rem', fontWeight: 'bold', color: '#ef4444' }}>
                {totalThreats}
              </div>
              <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase' }}>Total Threats</div>
            </div>

            <div style={{ 
              background: 'rgba(51, 65, 85, 0.5)', 
              padding: '15px', 
              borderRadius: '8px', 
              textAlign: 'center',
              border: '1px solid rgba(59, 130, 246, 0.3)'
            }}>
              <div style={{ fontSize: '2rem', fontWeight: 'bold', color: '#3b82f6' }}>
                {uniqueTypes}
              </div>
              <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase' }}>Threat Types</div>
            </div>

            <div style={{ 
              background: 'rgba(51, 65, 85, 0.5)', 
              padding: '15px', 
              borderRadius: '8px', 
              textAlign: 'center',
              border: '1px solid rgba(16, 185, 129, 0.3)'
            }}>
              <div style={{ fontSize: '2rem', fontWeight: 'bold', color: '#10b981' }}>
                {avgConfidence}%
              </div>
              <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase' }}>Avg Confidence</div>
            </div>
          </div>

          {/* Threats List */}
          <div style={{ background: 'rgba(51, 65, 85, 0.3)', borderRadius: '8px', padding: '1rem' }}>
            <h3 style={{ margin: '0 0 1rem 0', color: '#e2e8f0', fontSize: '1rem' }}>📋 Detected Threats Details</h3>
            <div style={{ maxHeight: '300px', overflowY: 'auto' }}>
              {threats.map((threat, index) => (
                <div 
                  key={index}
                  style={{
                    padding: '15px',
                    margin: '10px 0',
                    border: '1px solid rgba(148, 163, 184, 0.2)',
                    borderRadius: '8px',
                    backgroundColor: 'rgba(71, 85, 105, 0.3)',
                    borderLeft: `3px solid ${threat.confidence >= 90 ? '#ef4444' : threat.confidence >= 75 ? '#f59e0b' : '#eab308'}`
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                      <span style={{ 
                        padding: '0.25rem 0.5rem', 
                        backgroundColor: 'rgba(59, 130, 246, 0.2)', 
                        color: '#93c5fd', 
                        borderRadius: '4px', 
                        fontSize: '0.75rem' 
                      }}>
                        {threat.type.replace(/_/g, ' ')}
                      </span>
                      <span style={{ color: '#e2e8f0', fontWeight: '500' }}>{threat.label}</span>
                    </div>
                    <span style={{ color: '#94a3b8', fontSize: '0.875rem', fontFamily: 'Courier New, monospace' }}>
                      {Math.floor(threat.timestamp / 1000)}s
                    </span>
                  </div>
                  <div style={{ position: 'relative', height: '6px', backgroundColor: 'rgba(71, 85, 105, 0.5)', borderRadius: '3px', overflow: 'hidden' }}>
                    <div style={{
                      width: `${threat.confidence}%`,
                      height: '100%',
                      background: 'linear-gradient(90deg, #ef4444, #f59e0b, #10b981)',
                      borderRadius: '3px'
                    }} />
                    <span style={{ 
                      position: 'absolute', 
                      right: '0', 
                      top: '-20px', 
                      fontSize: '0.75rem', 
                      color: '#cbd5e1' 
                    }}>
                      {Math.round(threat.confidence)}%
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ThreatDashboard;
