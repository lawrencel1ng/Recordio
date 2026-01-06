import os
import urllib.request
import ssl
import sys

def download_lfs_file(filepath, url):
    print(f"Downloading {filepath} from {url}...")
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        with urllib.request.urlopen(url, context=ctx) as response:
            if response.status == 200:
                with open(filepath, 'wb') as f:
                    while True:
                        chunk = response.read(8192)
                        if not chunk:
                            break
                        f.write(chunk)
                print(f"Successfully downloaded {filepath}")
            else:
                print(f"Failed to download {filepath}: {response.status}")
    except Exception as e:
         print(f"Failed to download {filepath}: {e}")

def process_directory(root_dir, base_url):
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            
            # Check if file is small enough to be a potential LFS pointer
            if os.path.getsize(filepath) < 1024:
                try:
                    with open(filepath, 'r') as f:
                        content = f.read()
                    
                    if content.startswith('version https://git-lfs.github.com/spec/v1'):
                        # It's an LFS pointer! Construct LFS download URL
                        rel_path = os.path.relpath(filepath, root_dir)
                        # Encode path parts to handle potential special chars, though typical filenames are safe
                        encoded_path = "/".join([urllib.parse.quote(part) for part in rel_path.split(os.sep)])
                        download_url = f"{base_url}/{encoded_path}"
                        
                        download_lfs_file(filepath, download_url)
                except Exception as e:
                    # Not a text file or read error, skipping
                    pass

if __name__ == "__main__":
    repo_path = "/Users/lawrenceling/Development/Recordio/TempModels/repo"
    hf_url = "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main"
    
    if not os.path.exists(repo_path):
        print(f"Repo path {repo_path} does not exist. Re-cloning...")
        os.system(f"git clone --depth 1 https://huggingface.co/FluidInference/speaker-diarization-coreml {repo_path}")

    process_directory(repo_path, hf_url)
