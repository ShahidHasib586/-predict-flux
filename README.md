# Flux Predictor App

FluxPredictorApp is a MATLAB App Designer–style UI for estimating membrane distillation flux based on six operating parameters. The app loads the accompanying `MDData.xlsx` dataset, fits a linear regression model with the numeric predictors, and displays the predicted flux along with a parity plot of training data.

## Requirements
- MATLAB R2020b or newer (requires App Designer UI components and Statistics and Machine Learning Toolbox for `fitlm`).
- The `FluxPredictorApp.m` file and `MDData.xlsx` dataset must be in the same folder.

## Usage
1. Open the folder containing `FluxPredictorApp.m` in MATLAB.
2. Launch the app from the MATLAB Command Window:
   ```matlab
   app = FluxPredictorApp;
   ```
3. Adjust the input fields for feed temperature, cold temperature, hot and cold flow rates, membrane pore size, and thickness.
4. Click **Predict now** to update the predicted flux label.
5. Click **Reload & retrain** if you modify `MDData.xlsx`; the app will reload the data, refit the linear model, and refresh the training fit plot.

## Notes
- Missing values in `MDData.xlsx` are dropped before training.
- The training plot shows measured flux versus the model prediction for the current dataset.
