# Python API Example

Simple Flask API to demonstrate Docker Sandboxes for Python development.

## Run with Docker Sandbox

```bash
cd examples/python-api
docker sandbox run claude
```

## Example Prompts for Claude

1. **"Set up the Flask application and install dependencies"**
   - Claude will create a virtual environment
   - Install requirements
   - Set up the basic structure

2. **"Create a simple REST API with health check and user endpoints"**
   - Claude will implement the API
   - Add proper error handling
   - Include tests

3. **"Add logging and run the development server"**
   - Configure logging
   - Start the Flask dev server
   - Test the endpoints

## Expected Structure

```
python-api/
├── app.py              # Main Flask application
├── requirements.txt    # Python dependencies
├── tests/             # Test files
│   └── test_app.py
├── .env.example       # Environment variables template
└── README.md          # This file
```

## Benefits of Using Sandbox

- ✅ Dependencies isolated from host Python
- ✅ Safe experimentation with packages
- ✅ Easy cleanup (just remove the sandbox)
- ✅ Reproducible environment
