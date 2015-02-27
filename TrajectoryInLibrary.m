classdef TrajectoryInLibrary
  % A class for trajectories inside the TrajectoryLibrary.
  
  properties
    xtraj;
    utraj;
    lqrsys; % LQR controller
    state_frame; % state frame of the plant
    body_coordinate_frame;
  end
  
  methods
    
    function obj = TrajectoryInLibrary(xtraj, utraj, lqrsys, state_frame)
      
      typecheck(xtraj, 'Trajectory');
      
      if isa(utraj, 'ConstantTrajectory')
        utraj = PPTrajectory(utraj);
      end
      
      typecheck(utraj, 'Trajectory');
      
      obj.xtraj = xtraj;
      obj.utraj = utraj;
      
      obj.lqrsys = lqrsys;
      obj.state_frame = state_frame;
      
      obj.body_coordinate_frame = CoordinateFrame('body_frame_delta', 12, 'x');
      
      % add transform to/from the body frame
      to_est_frame = @(~, ~, x) TrajectoryInLibrary.ConvertXVectorToEstimatorFrame(x);
      to_drake_frame = @(~, ~, x) TrajectoryInLibrary.ConvertXVectorToDrakeFrame(x);
      
      trans_to_est = FunctionHandleCoordinateTransform(12, 0, obj.state_frame, obj.body_coordinate_frame, true, true, to_est_frame, to_est_frame, to_est_frame);
      trans_to_drake = FunctionHandleCoordinateTransform(12, 0, obj.body_coordinate_frame, obj.state_frame, true, true, to_drake_frame, to_drake_frame, to_drake_frame);
      obj.state_frame.addTransform(trans_to_est);
      obj.body_coordinate_frame.addTransform(trans_to_drake);
      
      %obj.xtraj = obj.xtraj.setOutputFrame(obj.state_frame);
      
    end
    
    function WriteToFile(obj, filename_prefix, dt, overwrite_files)
      %
      % Write files that contain the trajectory information in filename.csv and
      % filename-u.csv or filename-affine.csv or filename-controller.csv
      %
      % @param filename_prefix filename_prefix to write files to (aka
      % filename_prefix-u.csv)
      % @param dt sampling time for trajectory
      % @param overwrite_files set to true to overwrite
      %   @default false
      
      if nargin < 4
        overwrite_files = false;
      end

      state_filename = [filename_prefix '-x.csv'];
      
      u_filename = [filename_prefix '-u.csv'];
      
      controller_filename = [filename_prefix '-controller.csv'];
      
      affine_filename = [filename_prefix '-affine.csv'];
      
      if ~overwrite_files && exist(state_filename, 'file') ~= 0
        error(['Not writing trajectory since "' state_filename '" exists.']);
      end
      
      if ~overwrite_files && exist(u_filename, 'file') ~= 0
        error(['Not writing trajectory since "' u_filename '" exists.']);
      end
      
      if ~overwrite_files && exist(controller_filename, 'file') ~= 0
        error(['Not writing trajectory since "' controller_filename '" exists.']);
      end
      
      if ~overwrite_files && exist(affine_filename, 'file') ~= 0
        error(['Not writing trajectory since "' affine_filename '" exists.']);
      end
      
      xpoints = [];

      breaks = obj.xtraj.getBreaks();
      endT = breaks(end);

      counter = 1;
      for t = 0:dt:endT
          xpoints(:,counter) = [t; obj.xtraj.eval(t)];
          counter = counter + 1;
      end

      upoints = [];

      counter = 1;
      for t = 0:dt:endT
          upoints(:,counter) = [t; obj.utraj.eval(t)];
          counter = counter + 1;
      end
      
      Kpoints = [];
      
      kpoint_headers = {'t'};
      
      for i = 1 : obj.utraj.dim
        for j = 1:12
          kpoint_headers{end+1} = ['k' num2str(i) '_' num2str(j)];
        end
      end
           
      
      counter = 1;
      for t = 0:dt:endT
        
        this_k = obj.lqrsys.D.eval(t);
        
        col_k = [];
        
        for i = 1 : obj.utraj.dim
          col_k = [ col_k, this_k(i,:) ];
        end
        
        Kpoints(:, counter) = [t col_k];
          
        counter = counter + 1;
        
      end
      
      affine_points = [];

      counter = 1;
      for t = 0:dt:endT
          affine_points(:,counter) = [t; obj.lqrsys.y0.eval(t)];
          counter = counter + 1;
      end
      

      % write all the xpoints to a file
      
      xpoint_headers = { 't', 'x', 'y', 'z', 'roll', 'pitch', 'yaw', 'xdot', 'ydot', 'zdot', 'rolldot', 'pitchdot', 'yawdot'};

      disp(['Writing: ' state_filename]);
      TrajectoryInLibrary.csvwrite_wtih_headers(state_filename, xpoint_headers, xpoints');
      
      upoint_headers = { 't', 'elevL', 'elevR', 'throttle'};
      
      disp(['Writing: ' u_filename]);
      TrajectoryInLibrary.csvwrite_wtih_headers(u_filename, upoint_headers, upoints');
      
      
      disp(['Writing: ' controller_filename]);
      TrajectoryInLibrary.csvwrite_wtih_headers(controller_filename, kpoint_headers, Kpoints');
      
      affine_headers = { 't', 'affine_elevL', 'affine_elevR', 'affine_throttle' };
      
      disp(['Writing: ' affine_filename]);
      TrajectoryInLibrary.csvwrite_wtih_headers(affine_filename, affine_headers, affine_points');
      

    end
    
    function converted_traj = ConvertToStateEstimatorFrame(obj)
      % Converts the object's internal trajectories into the frame used by
      % the onboard state estimator.
      %
      % @retval converted object

      xtraj_convert = obj.xtraj.inFrame(obj.body_coordinate_frame);
      lqrsys_convert = obj.lqrsys.inInputFrame(obj.body_coordinate_frame);
      
      converted_traj = TrajectoryInLibrary(xtraj_convert, obj.utraj, lqrsys_convert, obj.state_frame);
      
    end
    
    function converted_traj = ConvertToDrakeFrame(obj)
      % Converts the object's internal trajectories into the frame used by
      % Drake.
      %
      % @retval converted object
      
      xtraj_convert = obj.xtraj.inFrame(obj.state_frame);
      lqrsys_convert = obj.lqrsys.inInputFrame(obj.state_frame);
      
      converted_traj = TrajectoryInLibrary(xtraj_convert, obj.utraj, lqrsys_convert, obj.state_frame);
      
    end
    
  end
  
  methods (Static)
    
    function csvwrite_wtih_headers(filename, headers, array)
       
      assert(~isempty(headers), 'No headers?');
      
      head_str = headers{1};
      
      for i = 2 : length(headers)
        head_str = [ head_str, ', ', headers{i}];
      end
      
      fid = fopen(filename, 'w');
      fprintf(fid, '%s\r\n', head_str);
      fclose(fid);
      
      dlmwrite(filename, array, '-append', 'delimiter', ',');
      
    end
    
    function x_est_frame = ConvertXVectorToEstimatorFrame(x_drake_frame)
      % Converts the 12-dimensional vector for the aircraft's state into
      % one that works for the state esimator and should be exported and
      % used for online control
      %
      % Output state: x, y, z (global frame), roll, pitch, yaw, xdot, ydot,
      % zdot (body frame), angular velocity (3 numbers)
      %
      % @param x_drake_frame input state
      %
      % @retval x_est_frame output state
      
      % global position stays in the global frame
      
      % Drake frame:
      % x(1:3): x,y,z, in global frame (ENU coordinates)
      % x(4:6): rpy
      % x(7:9): xdot, ydot, zdot, in global frame (ENU coordinates)
      % x(10:12): rdot, pdot, ydot
      
      % State estimator frame:
      %
      % double pos[3];              // position x,y,z in meters in local frame (ENU coordinates)
      % double vel[3];              // velocity in m/s, expressed in body frame
      % 
      % double orientation[4];      // rotate vector in body coordinate frame 
      %                             // (X-forward, Z-down) by this to get that vector
      %                             // in local frame
      % 
      % double rotation_rate[3];    // angular velocity vector of the vehicle
      %                             // in rad/s.  This is expressed in the body
      %                             // frame.
      
      % get the rotation matrix for this rpy
      
      % Compute U,V,W from xdot,ydot,zdot
      
      x_est_frame(1:6,:) = x_drake_frame(1:6);
      
      rpy = x_drake_frame(4:6);
      xdot = x_drake_frame(7);
      ydot = x_drake_frame(8);
      zdot = x_drake_frame(9);
      
      rolldot = x_drake_frame(10);
      pitchdot = x_drake_frame(11);
      yawdot = x_drake_frame(12);
      
      R_body_to_world = rpy2rotmat(rpy);
      R_world_to_body = R_body_to_world';
      UVW = R_world_to_body*[xdot;ydot;zdot];

      % Compute P,Q,R (angular velocity components)
      pqr = rpydot2angularvel(rpy,[rolldot;pitchdot;yawdot]); % in world frame
      PQR = R_world_to_body*pqr; % body coordinate frame
      
      x_est_frame(7:9) = UVW;
      
      x_est_frame(10:12) = PQR;
      
    end
    
    function x_drake_frame = ConvertXVectorToDrakeFrame(x_est_frame)
      % Converts the 12-dimensional vector for the aircraft's state from
      % the state estimator into the Drake frame.
      %
      % Output state: x, y, z (global frame), roll, pitch, yaw, xdot, ydot,
      % zdot (global frame), rolldot, pitchdot, yawdot
      %
      % @param x_est_frame input state
      %
      % @retval x_drake_frame output state
      
      x_drake_frame(1:6, :) = x_est_frame(1:6);
      
      rpy = x_est_frame(4:6);
      UVW = x_est_frame(7:9);
      
      R_body_to_world = rpy2rotmat(rpy);
      
      vel_world = R_body_to_world  * UVW;
      
      x_drake_frame(7:9) = vel_world;
      
      PQR = x_est_frame(10:12); % in body frame
      
      pqr = R_body_to_world * PQR; % in world frame
      
      rpydot = angularvel2rpydot(rpy, pqr);
      
      x_drake_frame(10:12) = rpydot;
      
      
    end
    
    
  end
  
end