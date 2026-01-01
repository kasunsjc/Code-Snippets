"""
Simple Flask API - Advanced Multi-Stage Build Demo
This demonstrates advanced DHI usage with multi-stage builds.
"""

from flask import Flask, jsonify, request
import os
import platform

app = Flask(__name__)

@app.route('/')
def home():
    """Home endpoint"""
    return jsonify({
        'message': 'Hello from Advanced DHI Multi-Stage Build!',
        'status': 'running',
        'version': '1.0.0',
        'image_type': 'dhi-advanced',
        'security': 'maximum-hardened',
        'build_type': 'multi-stage',
        'python_version': platform.python_version(),
        'platform': platform.platform()
    })

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'demo-app-dhi-advanced'
    }), 200

@app.route('/info')
def info():
    """System information endpoint"""
    return jsonify({
        'hostname': platform.node(),
        'system': platform.system(),
        'release': platform.release(),
        'python_version': platform.python_version(),
        'user': os.getenv('USER', 'nonroot'),
        'uid': os.getuid() if hasattr(os, 'getuid') else 'N/A',
        'gid': os.getgid() if hasattr(os, 'getgid') else 'N/A',
        'security_note': 'Multi-stage build with DHI - Maximum security'
    })

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=False)
