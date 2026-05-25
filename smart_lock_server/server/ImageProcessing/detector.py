from numpy.linalg import norm
import numpy as np
from insightface.app import FaceAnalysis

class FaceDetector:
    def __init__(self,app:FaceAnalysis,det_size:tuple=(640,640),device:str='cpu'):
        self.app = app
        self.prepare(det_size=det_size,device=device)

    def prepare(self,det_size:tuple=(320,320),device:str='cpu'):
        self.app.prepare(ctx_id=0 if device=='cuda' else -1, det_size=det_size)

    def compute_similarity(embedding1, embedding2):
    # Tính tích vô hướng (dot product) chia cho tích độ dài (norm) của 2 vector
        sim = np.dot(embedding1, embedding2) / (norm(embedding1) * norm(embedding2))
        return sim

    def getEmbedding(self,img):
        faces = self.app.get(img)
        if len(faces) > 0:
            return faces[0].embedding
        else:
            return None

    def isMatch(self,embedding1,embedding2, threshold=0.45)->bool:
        sim = self.compute_similarity(embedding1,embedding2)
        return sim >= threshold
    