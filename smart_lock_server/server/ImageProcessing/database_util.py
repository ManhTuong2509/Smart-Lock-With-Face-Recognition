import faiss
import numpy as np
import json
import os

class FaceDatabase:
    def __init__(self, dimension=512, index_file="data/faiss_index.bin", meta_file="data/faiss_meta.json"):
        """
        Initializes the Faiss Database wrapper.
        dimension: 512 is the default embedding size for InsightFace's Buffalo_l model.
        """
        self.dimension = dimension
        self.index_file = index_file
        self.meta_file = meta_file
        
        # Ensure data directory exists
        os.makedirs(os.path.dirname(os.path.abspath(self.index_file)), exist_ok=True)
        
        self.index = None
        self.metadata = [] # List of dicts, index corresponds to the faiss internal ID
        
        self.load()

    def load(self):
        """Loads the Faiss index and metadata from disk if they exist."""
        if os.path.exists(self.index_file) and os.path.exists(self.meta_file):
            self.index = faiss.read_index(self.index_file)
            with open(self.meta_file, 'r') as f:
                self.metadata = json.load(f)
            print(f"Loaded {self.index.ntotal} faces from database.")
        else:
            # IndexFlatIP uses Cosine Similarity. Since InsightFace embeddings 
            # are typically normalized, Cosine Similarity is highly effective for similarity search.
            self.index = faiss.IndexFlatIP(self.dimension)
            self.metadata = []
            print("Created a new, empty Face Database.")

    def save(self):
        """Saves the Faiss index and metadata to disk."""
        faiss.write_index(self.index, self.index_file)
        with open(self.meta_file, 'w') as f:
            json.dump(self.metadata, f)

    def add_face(self, embedding, user_name, user_id=None, image_path=None, registered_at=None):
        """
        Adds a new face embedding to the database.
        embedding: numpy array representing the face
        """
        if embedding.ndim == 1:
            embedding = np.expand_dims(embedding, axis=0)
            
        embedding = embedding.astype('float32')
        
        # Normalize the embedding to unit length for Cosine Similarity (in-place)
        faiss.normalize_L2(embedding)
        # The internal Faiss ID will match the length of our metadata list before we append
        current_id = self.index.ntotal
        
        self.index.add(embedding)
        
        self.metadata.append({
            "faiss_id": current_id,
            "user_name": user_name,
            "user_id": user_id,
            "image_path": image_path,
            "registered_at": registered_at
        })
        
        self.save()
        print(f"Successfully added {user_name} to database.")
        return current_id

    def search_face(self, embedding, k=1, threshold=0.45):
        """
        Searches for the closest face in the database.
        threshold: Maximum L2 distance. You will need to tune this! 
                   (Usually around 1.0 - 1.2 for InsightFace normalized embeddings)
        """
        if self.index.ntotal == 0:
            return None, None
            
        if embedding.ndim == 1:
            embedding = np.expand_dims(embedding, axis=0)
            
        embedding = embedding.astype('float32')
        
        # Normalize the embedding to unit length for Cosine Similarity (in-place)
        faiss.normalize_L2(embedding)
        # Perform the search
        distances, indices = self.index.search(embedding, k)
        
        best_distance = distances[0][0]
        best_index = indices[0][0]
        
        # If match is found and falls within our acceptable threshold
        if best_index != -1 and best_distance > threshold:
            match_meta = self.metadata[best_index]
            return match_meta, float(best_distance)
        
        # Return None if it's an "Unknown" face (distance too low)
        return None, float(best_distance)
