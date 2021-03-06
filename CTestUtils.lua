local testUtils = {}



--[[

  This is function is for visualization of distance matrix. In takes as input _distNet_, _input_, _target_
  and _index_ and outputs _distMatrix_ and _gtDistMatrix_
  
  _distNet_ is network that computes distance matrix for two epipolar lines
  
  _input_ is table consisting of _refEpi_ and _posEpi_ tensors
    _refEpi_ is nb_samples x (2*hpatch + 1) x (im_w) tensor 
    _posEpi_ is nb_samples x (2*hpatch + 1) x (im_w) tensor 
  
  _target_ is gt disparities of _patch_ in _epi_ (with inf in unknow val).

  _distMat_ is nb_samples x (im_w - 2*hpatch) x (img_w - 2*hpatch) tensor of predicted simularity matrices
  _gtDistMat_ is nb_samples x (im_w - 2*hpatch) x (img_w - 2*hpatch) tensor of gt simularity matrices
  
  You should take care about parameters of network!
  
]]--

function testUtils.getDist(distNet, input, target, errTh)
  
  local nb_samples = input[1]:size(1);
  local refEpi, posEpi = unpack(input) 
  local hpatch = (refEpi:size(2)-1)/2
  local im_w = refEpi:size(3)
  local row = torch.range(1, im_w - 2*hpatch);
    
  local distMat = -torch.ones(nb_samples, im_w - 2*hpatch, im_w - 2*hpatch);
  local gtDistMat = -torch.ones(nb_samples, im_w - 2*hpatch, im_w - 2*hpatch);
  
  for nsample = 1, nb_samples do

    local gtDisp = target[{{nsample}, {}}]:double():squeeze();
    local rowCol = torch.add(row, -gtDisp) -- here we compute col indices in distance matrix 
    
    for nrow = 1, gtDisp:size(1) do
      if( gtDisp[nrow] ~= -1 ) then
        for ddisp = -errTh, errTh do
          if( rowCol[nrow]+ddisp >= 1 and rowCol[nrow]+ddisp <= im_w - 2*hpatch ) then
            gtDistMat[{{nsample},{nrow},{rowCol[nrow]+ddisp}}] = 1; 
          end
        end
      end
    end
    
    local sample_input = {refEpi[{{nsample}, {}, {}}], posEpi[{{nsample}, {}, {}}]}
    distMat[{{nsample},{},{}}] = distNet:forward(sample_input):double() 
    
  end
  
  return distMat, gtDistMat
  
end


--[[

  This is function for testing network accuracy. In takes as input _distNet_, _input_, _target_
  and outputs _accuracy_ and _errorCases_
  
  _distNet_ is network that computes distance matrix for two epipolar lines
  
  _input_ is table consisting of _refEpi_ and _posEpi_ tensors
    _refEpi_ is nb_samples x (2*hpatch + 1) x (im_w) tensor 
    _posEpi_ is nb_samples x (2*hpatch + 1) x (im_w) tensor 
  
  _target_ is gt disparities of _patch_ in _epi_ (with inf in unknow val).

  _accuracy_ is % of all predictions that ||d-d_gt|| < _errTh_
  
  _errorCases_ is table that consist of _refPatch_, _solPatch_, _gtPatch_ and _dispErr_ 
    _refPatch_ is nb_err_samples x (2*hpatch+1) x (2*hpatch+1) tensor reference patches
    _solPatch_ is nb_err_samples x (2*hpatch+1) x (2*hpatch+1) tensor of predicted matches 
    _gtPatch_ is nb_err_samples x (2*hpatch+1) x (2*hpatch+1) tensor of true matches, according to gt
    
  You should take care about parameters of network!
  
]]--


function testUtils.getPatch(epi,x)
    
    
    local nb_patch = x:size(1)
    local hpatch = (epi:size(2)-1)/2
    local patch = torch.Tensor(nb_patch, 2*hpatch+1, 2*hpatch+1)
    
    for npatch = 1, nb_patch do
      patch[{{npatch},{},{}}] = epi[{{1},{},{x[npatch]-hpatch, x[npatch]+hpatch}}]:squeeze():double():clone()
    end
    
    return patch
end


function testUtils.getGraph(distNet, input, target, errTh)
  
  
  
  local nb_samples = input[1]:size(1);
  local refEpi, posEpi = unpack(input) 
  local hpatch = (refEpi:size(2)-1)/2
  local im_w = refEpi:size(3)
  local row = torch.range(1, im_w - 2*hpatch);
    
  local ref = {}
  local sol = {}
  local gt = {}
  local dispErr = {}
  local err = {}
  nb_disp = 100
  
  nGtDispCum = 0
  for nsample = 1, nb_samples do

    -- get gt disparities
    local gtDisp      = target[{{nsample}, {}}]:double():squeeze();
    local nGtDisp = torch.sum(gtDisp:ne(-1):double())
    
    -- compute positive similarity
    local sample_input = {refEpi[{{nsample}, {}, {}}], posEpi[{{nsample}, {}, {}}]}
    local distMat = distNet:forward(sample_input):double() 
        
    nTrueSol = {}
    
    for nbest = 1, 100 do
    
      -- compute best disparity
      local maxVal, maxInd = torch.max(distMat, 2)  
      wtaDisp = maxInd:double()
      wtaDisp = torch.add(row, -wtaDisp) -- here we compute real disparities 
    
      -- compute % of true disparities not covered by 1..n-th maximums
      local dispDiff = torch.abs(wtaDisp-gtDisp)
      local failMask = gtDisp:ne(-1)
      failMask = failMask:cmul(dispDiff:lt(errTh))
      nTrueSol[nbest] = torch.sum(failMask)
      
      -- mark gt disp already covered 
      gtDisp[failMask] = -1
      
      -- mask 
      distMat = distMat:scatter(2, maxInd, -1/0)
     
    end
    
    if( nsample == 1 ) then
      nTrueSolCum = torch.Tensor(nTrueSol)
      nGtDispCum = nGtDisp
    else
      nGtDispCum =  nGtDispCum + nGtDisp
      nTrueSolCum:add(torch.Tensor(nTrueSol))
    end
  end
  
  --nTrueSolCum = torch.cumsum(nTrueSolCum)/nGtDispCum

  return nTrueSolCum, nGtDispCum
end

function testUtils.getTestAcc(distNet, input, target, errTh)
  
   
  local nb_samples = input[1]:size(1);
  local refEpi, posEpi = unpack(input) 
  local hpatch = (refEpi:size(2)-1)/2
  local im_w = refEpi:size(3)
  local row = torch.range(1, im_w - 2*hpatch);
    
  local ref = {}
  local sol = {}
  local gt = {}
  local dispErr = {}
  local err = {}
     
  for nsample = 1, nb_samples do

    local gtDisp      = target[{{nsample}, {}}]:double():squeeze();
        
    local sample_input = {refEpi[{{nsample}, {}, {}}], posEpi[{{nsample}, {}, {}}]}
    
    local distMat = distNet:forward(sample_input):double() 
    
    local val, wtaDisp = torch.max(distMat, 2)  
    
    wtaDisp = wtaDisp:double()
        
    wtaDisp = torch.add(row, -wtaDisp) -- here we compute real disparities 
    
    local dispDiff = torch.abs(wtaDisp-gtDisp)
    dispErr[nsample] = dispDiff[gtDisp:ne(-1)]:double(); -- put on cpu
     
    -- save failure cases ( >= 3 px)
    local failMask = gtDisp:ne(-1)
    failMask = failMask:cmul(dispDiff:ge(errTh)) 
    local failIdx = row[failMask]

    if failMask:sum() > 0  then
             
      local refIdx = failIdx + hpatch
      local gtIdx  = failIdx - gtDisp[failMask] + hpatch 
      local solIdx = failIdx - wtaDisp[failMask] + hpatch 
             
      ref[#ref+1] = testUtils.getPatch(refEpi[{{nsample}, {}, {}}], refIdx:double())
      gt[#gt+1]  = testUtils.getPatch(posEpi[{{nsample}, {}, {}}], gtIdx:double())
      sol[#sol+1] = testUtils.getPatch(posEpi[{{nsample}, {}, {}}], solIdx:double())
      err[#err+1] = dispDiff[failMask]:double()
      
    end    
  end
  
  dispErr  = torch.cat(dispErr,1)
  
  errCases = {torch.cat(ref,1), torch.cat(sol,1), torch.cat(gt,1), torch.cat(err,1)}
  --acc = dispErr[dispErr:lt(errTh)]:numel() * 100 / dispErr:numel();
  
  return dispErr, errCases  
end

return testUtils