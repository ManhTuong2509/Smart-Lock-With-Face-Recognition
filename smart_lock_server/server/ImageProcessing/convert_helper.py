import numpy as np
import base64
import cv2

class ConvertHelper:
    @staticmethod
    def base64ToNumpy(base64_string):
        """
        Converts a base64 string to a numpy array.
        """
        base64_string = base64_string.replace("data:image/jpeg;base64,", "").replace("data:image/png;base64,", "")
        return np.frombuffer(base64.b64decode(base64_string), np.uint8)

    @staticmethod
    def numpyToBase64(numpy_array):
        """
        Converts a numpy array to a base64 string.
        """
        return base64.b64encode(numpy_array).decode("utf-8")

    @staticmethod
    def numpyToImage(numpy_array):
        """
        Converts a numpy array to an image.
        """
        return cv2.imdecode(numpy_array, cv2.IMREAD_COLOR)

    @staticmethod
    def imageToNumpy(image):
        """
        Converts an image to a numpy array.
        """
        return cv2.imencode(".jpg", image)[1]

    @staticmethod
    def imageToBase64(image):
        """
        Converts an image to a base64 string.
        """
        return ConvertHelper.numpyToBase64(ConvertHelper.imageToNumpy(image))