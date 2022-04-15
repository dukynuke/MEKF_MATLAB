%% The Multiplicative Extended Kalman Filter (MEKF) %%

clear all ; close all ; clc ; 

rng(0) ;
duration = 12 ;
fs = 100 ;
dt = 1/fs ; 
numSamples = fs*duration ;
accelerationBody = zeros(numSamples,3);
xAxisAccelerationBody = 0*[linspace(0,0,5*fs),1*ones(1,2*fs),linspace(0,0,5*fs)]';
yAxisAccelerationBody = 0*[linspace(0,4*pi,4*fs),4*pi*ones(1,4*fs),linspace(4*pi,0,4*fs)]';
zAxisAccelerationBody = 0*[linspace(0,4*pi,4*fs),4*pi*ones(1,4*fs),linspace(4*pi,0,4*fs)]';
accelerationBody(:,1) = xAxisAccelerationBody;
accelerationBody(:,2) = yAxisAccelerationBody;
accelerationBody(:,3) = zAxisAccelerationBody;
angularVelocityBody = zeros(numSamples,3);
xAxisAngularVelocity = pi/120*ones(1,1200)*1 ; % 0*[linspace(0,pi,4*fs),pi*ones(1,4*fs),linspace(pi,0,4*fs)]';
yAxisAngularVelocity = pi/120*ones(1,1200)*0 ;
zAxisAngularVelocity = 0*[linspace(0,4*pi,4*fs),4*pi*ones(1,4*fs),linspace(4*pi,0,4*fs)]';
angularVelocityBody(:,1) = xAxisAngularVelocity;
angularVelocityBody(:,2) = yAxisAngularVelocity;
angularVelocityBody(:,3) = zAxisAngularVelocity;

% Ground Truth
trajectory = kinematicTrajectory('SampleRate',fs);
[~,orientationNED,~,accelerationNED,angularVelocityNED] = trajectory(accelerationBody,angularVelocityBody);

% IMU Model
IMU = imuSensor('accel-gyro-mag','SampleRate',fs);
IMU.Accelerometer = accelparams( ...
    'MeasurementRange',Inf, ...
    'Resolution',0.00059875*0, ...
    'ConstantBias',0.4905*0, ...
    'AxesMisalignment',2*0, ...
    'NoiseDensity',20*1e-3*1, ...    % (m/s^2)/sqrt(Hz)
    'BiasInstability',0, ...
    'TemperatureBias', [0.34335 0.34335 0.5886]*0, ...
    'TemperatureScaleFactor', 0.02*0);
IMU.Gyroscope = gyroparams( ...
    'MeasurementRange',Inf, ...
    'Resolution',0.00059875*0, ...
    'ConstantBias',0*deg2rad(0.04)*[1 1 1], ...
    'AxesMisalignment',0, ...
    'NoiseDensity',deg2rad(0.4)*1, ...  % (rad/s)/sqrt(Hz)
    'BiasInstability',0, ...
    'TemperatureBias', [0.34335 0.34335 0.5886]*0, ...
    'TemperatureScaleFactor', 0.02*0);
IMU.Magnetometer = magparams( ...
    'MeasurementRange',Inf, ...                % uT
    'Resolution',0.3*0, ...                    % uT / LSB
    'TemperatureScaleFactor',0.1*0, ...        % % / degree C
    'ConstantBias',[40 40 40]*0, ...           % uT
    'TemperatureBias',[0.8 0.8 2.4]*0, ...     % uT / degree C
    'NoiseDensity',1*1e-3*[0.6 0.6 0.9]);       % uT / Hz^(1/2)
[accData,gyroData,magData] = IMU(accelerationNED,...
                                 angularVelocityNED,...
                                 orientationNED);

% Simulation and KF Parameters
q_true = quat2rotm(orientationNED) ; q_gyro = [0 0 0 1]' ; q_up = [0;0;0;1]' ;  
sig_a = (20*1e-3)*sqrt(fs) ;                % Std. Dev. of Accel. Noise
sig_m = norm(1e-3*[0.6 0.6 0.9])*sqrt(fs) ; % Std. Dev. of Mag. Noise
g_var = deg2rad(0.4)^2*sqrt(fs)*eye(3) ;    % Variance of Gyro Noise
G = -eye(3) ; H = eye(3) ; P = eye(3) ; Q = g_var/3 ; % KF Matrices

tic

for i=1:1200

R_true = q_true(:,:,i); % body->local
r_true(i) = rad2deg(atan2(R_true(3,2),R_true(3,3))) ;
p_true(i) = rad2deg(atan2(-R_true(3,1),sqrt(R_true(3,2)^2+R_true(3,3)^2))) ;
y_true(i) = rad2deg(atan2(R_true(2,1),R_true(1,1))) ; %

% Sensor Measurements
wx = gyroData(i,1) ; wy = gyroData(i,2) ; wz = gyroData(i,3) ; w = [wx wy wz] ;
ax = accData(i,1) ; ay = accData(i,2) ; az = accData(i,3) ;
accS = [ax ay az] ; accS = accS/norm(accS) ;  
ax = accS(1) ; ay = accS(2) ; az = accS(3) ;

% Time Update (Prediction)
F = -ssym(w) ;
P = F*P*F' + G*Q*G' ;

% Quaternion Propogation
q_gyro = q_gyro + 0.5*skew4(wx,wy,wz)*q_gyro*dt ;
q_prop = q_gyro/norm(q_gyro) ;
R_prop = quat_2_dcm(q_prop) ;
r_prop(i) = atan2(R_prop(2,3),R_prop(3,3)) ;
p_prop(i) = atan2(-R_prop(1,3),sqrt(R_prop(2,3)^2+R_prop(3,3)^2)) ;
y_prop(i) = atan2(R_prop(1,2),R_prop(1,1)) ; 

% TRIAD Algorithm  
R_TRIAD = TRIAD(accData(i,:)',magData(i,:)',[0;0;9.81],[27.555;-2.4169;-16.0849]) ;
R_TRIAD = R_TRIAD' ; 
r_triad(i) = atan2(R_TRIAD(2,3),R_TRIAD(3,3)) ;
p_triad(i) = atan2(-R_TRIAD(1,3),sqrt(R_TRIAD(2,3)^2+R_TRIAD(3,3)^2)) ;
y_triad(i) = atan2(R_TRIAD(1,2),R_TRIAD(1,1)) ;
q_TRIAD = dcm2quat(R_TRIAD) ; q_TRIAD = [q_TRIAD(2:end) q_TRIAD(1)]' ; 

% Measurement Update
del_q = qmul(q_TRIAD,qinv(q_prop)) ; 
e = (2*del_q(1:3)/del_q(4)) ;
bx = cross(accData(i,:)',magData(i,:)')/norm(cross(accData(i,:)',magData(i,:)')) ; 
R = (sig_m^2*(accData(i,:)'*accData(i,:))+...
    sig_a^2*(magData(i,:)'*magData(i,:)))/...
    norm(cross(accData(i,:)',magData(i,:)'))^2 + sig_m^2*bx*bx' ; 
K = P*H'*inv(H*P*H'+R) ;
P = (eye(3)-K*H)*P ;
diagsP(i,:) = diag(P) ;

% Reset
dX = K*e ; 
C = sqrt(1+(0.25*dX'*dX)) ; del_q = [0.5*dX/C;1/C] ; 
q_up = qmul(del_q,q_prop) ; 
dcm_up = quat_2_dcm(q_up) ; q_up = q_up/norm(q_up) ;
r_up(i) = atan2(dcm_up(2,3),dcm_up(3,3)) ;
p_up(i) = atan2(-dcm_up(1,3),sqrt(dcm_up(2,3)^2+dcm_up(3,3)^2)) ;
y_up(i) = atan2(dcm_up(1,2),dcm_up(1,1)) ;

end

toc

r_prop = [0 r_prop(1:1199)] ; p_prop = [0 p_prop(1:1199)] ; y_prop = [0 y_prop(1:1199)] ; 
r_up = [0 r_up(1:1199)] ; p_up = [0 p_up(1:1199)] ; y_up = [0 y_up(1:1199)] ; 

% figure ; plot(r_true) ; hold on ; plot(rad2deg(r_triad)) ; grid on ; 
% figure ; plot(p_true) ; hold on ; plot(rad2deg(p_triad)) ; grid on ; 
% figure ; plot(y_true) ; hold on ; plot(rad2deg(y_triad)) ; grid on ; 

% figure ; plot(r_true) ; hold on ; plot(rad2deg(r_prop)) ; grid on ; 
% figure ; plot(p_true) ; hold on ; plot(rad2deg(p_prop)) ; grid on ; 
% figure ; plot(y_true) ; hold on ; plot(rad2deg(y_prop)) ; grid on ; 

% figure ; plot(r_true) ; hold on ; plot(rad2deg(r_up)) ; grid on ; 
% figure ; plot(p_true) ; hold on ; plot(rad2deg(p_up)) ; grid on ; 
% figure ; plot(y_true) ; hold on ; plot(rad2deg(y_up)) ; grid on ; 

% Estimation Errors within Diagonal Bands' 3-Sigma
% figure ; 
% subplot(3,1,1) ; plot(3*sqrt(diagsP(:,1)),'b') ; hold on ; plot(-3*sqrt(diagsP(:,1)),'b') ; plot(deg2rad(r_true)-r_up,'r') ; grid on ;
% subplot(3,1,2) ; plot(3*sqrt(diagsP(:,2)),'b') ; hold on ; plot(-3*sqrt(diagsP(:,2)),'b') ; plot(deg2rad(p_true)-p_up,'r') ; grid on ;
% subplot(3,1,3) ; plot(3*sqrt(diagsP(:,3)),'b') ; hold on ; plot(-3*sqrt(diagsP(:,3)),'b') ; plot(deg2rad(y_true)-y_up,'r') ; grid on ;


RMSE_att = [sqrt(mean(((r_true' - rad2deg(r_up')).^2)));...
            sqrt(mean(((p_true' - rad2deg(p_up')).^2)));
            sqrt(mean(((y_true' - rad2deg(y_up')).^2)))] ;
        
RMSE_prop = [sqrt(mean(((r_true' - rad2deg(r_prop')).^2)));...
             sqrt(mean(((p_true' - rad2deg(p_prop')).^2)));
             sqrt(mean(((y_true' - rad2deg(y_prop')).^2)))] ;
         
RMSE_triad = [sqrt(mean(((r_true' - rad2deg(r_triad')).^2)));...
              sqrt(mean(((p_true' - rad2deg(p_triad')).^2)));
              sqrt(mean(((y_true' - rad2deg(y_triad')).^2)))] ;