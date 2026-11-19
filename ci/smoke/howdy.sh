# The CLI starts and its python imports resolve; no camera is needed.
howdy version
python -c 'import dlib, cv2, numpy'
for f in dlib_face_recognition_resnet_model_v1.dat mmod_human_face_detector.dat shape_predictor_5_face_landmarks.dat; do
	pacman -Qlq howdy | grep -q "/$f\$" || { echo "howdy: model $f is not packaged" >&2; exit 1; }
done
