import React, { useState, useCallback } from 'react';
import { useDropzone } from 'react-dropzone';

const VideoUpload = ({ apiUrl, onVideoUploaded, isAnalyzing }) => {
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploadStatus, setUploadStatus] = useState('idle');
  const [errorMessage, setErrorMessage] = useState('');

  const onDrop = useCallback(async (acceptedFiles) => {
    const file = acceptedFiles[0];
    if (!file) return;

    if (file.size > 100 * 1024 * 1024) {
      setErrorMessage('File size must be less than 100MB');
      setUploadStatus('error');
      return;
    }

    try {
      setUploadStatus('uploading');
      setUploadProgress(0);
      setErrorMessage('');

      console.log('Getting presigned URL from API...');
      
      // Step 1: Get presigned URL (small JSON request - no file)
      const response = await fetch(`${apiUrl}/upload-url`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          fileName: file.name,
          fileType: file.type
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API error: ${response.status} - ${errorText}`);
      }

      const { uploadUrl, key, fileUrl } = await response.json();
      console.log('Got presigned URL, uploading directly to S3...');
      console.log('Upload URL:', uploadUrl);

      // Step 2: Upload file to S3 using XMLHttpRequest (better CORS handling)
      const uploadResult = await new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        
        // Track upload progress
        xhr.upload.addEventListener('progress', (event) => {
          if (event.lengthComputable) {
            const progress = Math.round((event.loaded * 100) / event.total);
            setUploadProgress(progress);
            console.log(`S3 upload progress: ${progress}%`);
          }
        });

        // Handle successful upload
        xhr.addEventListener('load', () => {
          console.log(`S3 upload response status: ${xhr.status}`);
          if (xhr.status >= 200 && xhr.status < 300) {
            resolve({ success: true });
          } else {
            reject(new Error(`S3 upload failed: ${xhr.status} ${xhr.statusText}`));
          }
        });

        // Handle errors
        xhr.addEventListener('error', (event) => {
          console.error('S3 upload error:', event);
          reject(new Error('S3 upload failed: Network error'));
        });

        xhr.addEventListener('abort', () => {
          reject(new Error('S3 upload was aborted'));
        });

        // Configure and send the request
        xhr.open('PUT', uploadUrl, true);
        xhr.setRequestHeader('Content-Type', file.type);
        console.log('Starting S3 upload with XMLHttpRequest...');
        xhr.send(file);
      });

      console.log('S3 upload successful!');
      setUploadProgress(100);
      setUploadStatus('success');
      
      onVideoUploaded({
        name: file.name,
        key: key,
        url: fileUrl,
        size: file.size,
        type: file.type
      });

      setTimeout(() => {
        setUploadStatus('idle');
        setUploadProgress(0);
      }, 2000);

    } catch (error) {
      console.error('Upload error:', error);
      setUploadStatus('error');
      setErrorMessage(`Upload failed: ${error.message}`);
    }
  }, [apiUrl, onVideoUploaded]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'video/*': ['.mp4', '.avi', '.mov']
    },
    maxFiles: 1,
    disabled: uploadStatus === 'uploading' || isAnalyzing
  });

  return (
    <div className="video-upload">
      <h2>📤 Upload Video for Analysis</h2>
      
      <div 
        {...getRootProps()} 
        className={`dropzone ${isDragActive ? 'active' : ''} ${uploadStatus}`}
        style={{
          border: `2px dashed ${
            isDragActive ? '#3b82f6' : 
            uploadStatus === 'error' ? '#ef4444' : 
            uploadStatus === 'success' ? '#10b981' : '#64748b'
          }`,
          borderRadius: '8px',
          padding: '2rem',
          textAlign: 'center',
          cursor: uploadStatus === 'uploading' || isAnalyzing ? 'not-allowed' : 'pointer',
          backgroundColor: isDragActive ? 'rgba(59, 130, 246, 0.1)' : 
                          uploadStatus === 'error' ? 'rgba(239, 68, 68, 0.1)' :
                          uploadStatus === 'success' ? 'rgba(16, 185, 129, 0.1)' :
                          'rgba(51, 65, 85, 0.3)',
          minHeight: '150px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexDirection: 'column'
        }}
      >
        <input {...getInputProps()} />
        
        <div style={{ fontSize: '2rem', marginBottom: '1rem' }}>
          {uploadStatus === 'uploading' ? '⏳' : 
           uploadStatus === 'success' ? '✅' : 
           uploadStatus === 'error' ? '❌' : '📹'}
        </div>
        
        {uploadStatus === 'uploading' ? (
          <div style={{ width: '100%' }}>
            <p style={{ color: '#e2e8f0', marginBottom: '1rem' }}>
              Uploading to S3... {uploadProgress}%
            </p>
            <div style={{ 
              width: '100%', 
              height: '6px', 
              backgroundColor: 'rgba(71, 85, 105, 0.5)', 
              borderRadius: '3px', 
              overflow: 'hidden' 
            }}>
              <div 
                style={{ 
                  width: `${uploadProgress}%`, 
                  height: '100%', 
                  background: 'linear-gradient(90deg, #3b82f6, #06b6d4)', 
                  borderRadius: '3px',
                  transition: 'width 0.3s ease'
                }}
              />
            </div>
          </div>
        ) : uploadStatus === 'success' ? (
          <div style={{ color: '#10b981' }}>
            <p>✅ Upload successful!</p>
            <p style={{ fontSize: '0.875rem', color: '#94a3b8', marginTop: '0.5rem' }}>
              Video uploaded to S3 successfully
            </p>
          </div>
        ) : uploadStatus === 'error' ? (
          <div style={{ color: '#ef4444' }}>
            <p>❌ Upload Failed</p>
            <p style={{ fontSize: '0.875rem', marginTop: '0.5rem' }}>{errorMessage}</p>
          </div>
        ) : (
          <div>
            <p style={{ color: '#e2e8f0', marginBottom: '0.5rem' }}>
              {isDragActive ? 'Drop your video here' : 'Drag & drop a video file, or click to select'}
            </p>
            <p style={{ fontSize: '0.875rem', color: '#94a3b8' }}>
              Supports MP4, AVI, MOV files up to 100MB
            </p>
            <p style={{ fontSize: '0.75rem', color: '#64748b', marginTop: '0.5rem' }}>
              Uploads via presigned URL (XMLHttpRequest to S3)
            </p>
          </div>
        )}
      </div>

      {isAnalyzing && (
        <div style={{ marginTop: '1rem', textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}>
          <div style={{ 
            width: '16px', 
            height: '16px', 
            border: '2px solid #f3f3f3',
            borderTop: '2px solid #3398db',
            borderRadius: '50%',
            animation: 'spin 2s linear infinite'
          }} />
          <span style={{ color: '#94a3b8' }}>Analyzing video for threats...</span>
        </div>
      )}

      <style jsx>{`
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};

export default VideoUpload;
