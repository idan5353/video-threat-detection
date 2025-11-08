class WebSocketManager {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    
    // Callbacks
    this.onConnectionChange = null;
    this.onThreatDetected = null;
    this.onProcessingUpdate = null;
  }

  connect() {
    try {
      console.log('🔌 Attempting WebSocket connection to:', this.url);
      this.ws = new WebSocket(this.url);
      
      this.ws.onopen = () => {
        console.log('✅ WebSocket connected successfully');
        this.reconnectAttempts = 0;
        if (this.onConnectionChange) {
          this.onConnectionChange('connected');
        }
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          console.log('📨 WebSocket message received:', data);
          console.log('📋 Message action:', data.action);
          console.log('📋 Message alert_type:', data.alert_type);
          console.log('📋 Message status:', data.status);
          
          // Handle analysis_complete messages from threat analyzer
          if (data.action === 'analysis_complete') {
            console.log('🎯 Analysis complete message detected!');
            console.log('📊 Analysis results:', {
              threats_detected: data.threats_detected,
              threat_count: data.threat_count,
              summary: data.summary
            });
            
            // Treat as threat detection result (always call this for analysis results)
            if (this.onThreatDetected) {
              console.log('📞 Calling onThreatDetected callback');
              this.onThreatDetected(data);
            }
            
            // Also trigger processing complete
            if (this.onProcessingUpdate) {
              console.log('📞 Calling onProcessingUpdate callback');
              this.onProcessingUpdate({
                status: 'PROCESSING_COMPLETE',
                data: data,
                message: data.summary
              });
            }
          }
          // Handle legacy threat detection format
          else if (data.alert_type === 'THREAT_DETECTED' && this.onThreatDetected) {
            console.log('🚨 Legacy threat detected message');
            this.onThreatDetected(data);
          } 
          // Handle processing status updates
          else if (data.status && this.onProcessingUpdate) {
            console.log('🔄 Processing status update:', data.status);
            this.onProcessingUpdate(data);
          }
          // Handle unknown message formats
          else {
            console.log('⚠️ Unhandled message format:', data);
            console.log('💡 Expected: action="analysis_complete" OR alert_type="THREAT_DETECTED" OR status field');
          }
          
        } catch (error) {
          console.error('❌ Error parsing WebSocket message:', error);
          console.error('📄 Raw message data:', event.data);
        }
      };

      this.ws.onclose = (event) => {
        console.log('🔌 WebSocket disconnected. Code:', event.code, 'Reason:', event.reason);
        if (this.onConnectionChange) {
          this.onConnectionChange('disconnected');
        }
        
        // Auto-reconnect logic (optional)
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++;
          console.log(`🔄 Attempting reconnection ${this.reconnectAttempts}/${this.maxReconnectAttempts}...`);
          setTimeout(() => {
            this.connect();
          }, 2000 * this.reconnectAttempts); // Exponential backoff
        }
      };

      this.ws.onerror = (error) => {
        console.error('❌ WebSocket error:', error);
        if (this.onConnectionChange) {
          this.onConnectionChange('error');
        }
      };
      
    } catch (error) {
      console.error('❌ Failed to create WebSocket connection:', error);
      if (this.onConnectionChange) {
        this.onConnectionChange('error');
      }
    }
  }

  disconnect() {
    console.log('🔌 Manually disconnecting WebSocket');
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.reconnectAttempts = 0;
  }

  // Method to send messages (if needed in the future)
  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        this.ws.send(JSON.stringify(message));
        console.log('📤 Sent WebSocket message:', message);
      } catch (error) {
        console.error('❌ Error sending WebSocket message:', error);
      }
    } else {
      console.warn('⚠️ WebSocket not connected, cannot send message');
    }
  }

  // Get current connection status
  getStatus() {
    if (!this.ws) return 'disconnected';
    
    switch (this.ws.readyState) {
      case WebSocket.CONNECTING:
        return 'connecting';
      case WebSocket.OPEN:
        return 'connected';
      case WebSocket.CLOSING:
        return 'closing';
      case WebSocket.CLOSED:
        return 'disconnected';
      default:
        return 'unknown';
    }
  }
}

export default WebSocketManager;
